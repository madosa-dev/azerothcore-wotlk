/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

// The dashboard's admin console, server side.
//
// The dashboard never opens a socket into the game process - that was this
// module's founding promise and it still holds. Instead the web server writes a
// row into `live_dashboard_commands` and this tick picks it up, runs it, and
// writes the output back. Two things fall out of that for free: an admin action
// survives the web server being restarted mid-command, and there is a permanent
// record of every command anyone ran.
//
// Commands go through CliHandler - the same path the server console uses, with
// the same rights. That is deliberate: an admin console that can only do a
// curated list of things is not an admin console. The gate is at the other end,
// in server.py: a shared token, and localhost-only binding unless you go out of
// your way. See the module README before exposing it to a network.
//
// CliHandler takes a plain function pointer plus a void* for state, so the
// output is collected into a std::string passed as that argument.

#include "CharacterDatabase.h"
#include "Chat.h"
#include "GameTime.h"
#include "Log.h"
#include "ScriptMgr.h"

#include <string>
#include <vector>

namespace
{
    // Every poll is a synchronous database round-trip on the world thread, so
    // the interval is a direct trade against how long a dashboard button takes
    // to answer. Two seconds is imperceptible on a button and halves a cost the
    // world tick pays whether anyone is using the panel or not.
    constexpr uint32 ADMIN_POLL_INTERVAL_MS = 2000;

    // One command per tick at most. A dashboard button is not a batch job, and
    // this keeps a slow command (".server shutdown", a big ".gm" sweep) from
    // stacking several deep inside a single world update.
    constexpr uint32 MAX_COMMANDS_PER_TICK = 4;

    // MEDIUMTEXT could take far more, but an admin panel that has to render a
    // megabyte of output is not helping anyone.
    constexpr size_t MAX_OUTPUT_CHARS = 16000;

    void CollectOutput(void* arg, std::string_view text)
    {
        std::string* out = static_cast<std::string*>(arg);
        if (out->size() >= MAX_OUTPUT_CHARS)
            return;

        // Carriage returns come along with console formatting and are noise in
        // a web panel - and worse, they are a line break to some readers, which
        // is what tore a single database row into several on the way out.
        std::string clean;
        clean.reserve(text.size());
        for (char c : text)
            if (c != '\r')
                clean.push_back(c);

        // An empty piece is the formatting talking, not the command. Appending
        // a newline for it is what doubled every blank line in the panel.
        if (clean.empty())
            return;

        out->append(clean);
        if (clean.back() != '\n')
            out->push_back('\n');
    }

    std::string Escape(std::string value)
    {
        size_t pos = 0;
        while ((pos = value.find_first_of("'\\", pos)) != std::string::npos)
        {
            value.insert(pos, 1, '\\');
            pos += 2;
        }
        return value;
    }

    void RunPending()
    {
        QueryResult result = CharacterDatabase.Query(
            "SELECT id, command FROM live_dashboard_commands WHERE status = 'pending' ORDER BY id LIMIT {}",
            MAX_COMMANDS_PER_TICK);

        if (!result)
            return;

        std::vector<std::pair<uint64, std::string>> queued;
        do
        {
            Field* fields = result->Fetch();
            queued.emplace_back(fields[0].Get<uint64>(), fields[1].Get<std::string>());
        } while (result->NextRow());

        for (auto const& [id, command] : queued)
        {
            std::string output;
            CliHandler handler(&output, &CollectOutput);

            LOG_INFO("module", "mod-live-dashboard: admin command #{}: {}", id, command);

            bool ok = false;
            try
            {
                ok = handler.ParseCommands(command);
            }
            catch (std::exception const& e)
            {
                output += std::string("exception: ") + e.what();
            }

            if (output.empty())
                output = ok ? "(no output)" : "Unknown command, or it produced no output.";

            if (output.size() > MAX_OUTPUT_CHARS)
            {
                output.resize(MAX_OUTPUT_CHARS);
                output += "\n... (truncated)";
            }

            CharacterDatabase.Execute(
                "UPDATE live_dashboard_commands SET status = '{}', output = '{}', executed_at = {} WHERE id = {}",
                ok ? "done" : "failed", Escape(output),
                uint32(GameTime::GetGameTime().count()), id);
        }
    }
}

class live_admin_world : public WorldScript
{
    uint32 _timer = 0;

public:
    live_admin_world() : WorldScript("live_admin_world") { }

    void OnUpdate(uint32 diff) override
    {
        _timer += diff;
        if (_timer < ADMIN_POLL_INTERVAL_MS)
            return;

        _timer = 0;
        RunPending();
    }
};

void AddSC_live_admin()
{
    new live_admin_world();
}
