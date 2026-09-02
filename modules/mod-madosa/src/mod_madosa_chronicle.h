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

#ifndef MOD_MADOSA_CHRONICLE_H
#define MOD_MADOSA_CHRONICLE_H

#include "Define.h"

#include <string>

class Player;

// Writes this module's own events into mod-live-dashboard's `live_chronicle`
// table - see mod_madosa_chronicle.cpp for why the coupling is a table rather
// than a header. Every call is a no-op when that table is not installed, so
// nothing here needs guarding at the call site.
namespace MadosaChronicle
{
    void Record(std::string const& kind, Player const* actor, Player const* target = nullptr,
                int64 value = 0, std::string const& detail = "");
}

#endif
