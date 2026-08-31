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

#ifndef MOD_MADOSA_WORLDFORGED_H
#define MOD_MADOSA_WORLDFORGED_H

#include "Define.h"

#include <string>
#include <vector>

// The small surface the ".madosa worldforged" GM commands drive; everything
// else about the event lives in mod_madosa_worldforged.cpp.
namespace MadosaWorldforged
{
    // Forges a cache right now, ignoring the interval but not the other rules
    // (a spawn point still has to exist, and a real player still has to be
    // online for one to be picked for). Returns false and fills outError when
    // it could not.
    bool ForgeNow(std::string& outError);

    // Removes every cache currently standing, without announcing anything.
    // Returns how many were removed.
    uint32 ClearAll();

    // One human-readable line per standing cache, for ".madosa worldforged
    // status". Empty when nothing is out there.
    std::vector<std::string> Status();
}

#endif
