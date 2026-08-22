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

// Grab-bag module for small, ongoing custom server tweaks that don't warrant
// a dedicated module of their own (see README.md). Nothing needs a C++ hook
// yet - the current content (free_starter_mounts.sql) is pure DB data. This
// file exists so the build system recognizes mod-madosa as a module at all
// (a module needs a non-empty src/ to be picked up, which is also what makes
// its data/sql/db-*/ get applied by the DB updater) and as the place to
// declare/call new scripts as they're added:
//
// void AddSC_something();

void AddSC_madosa_misc()
{
    // Add new custom scripts here as they're written.
}

// Add all
void Addmod_madosaScripts()
{
    AddSC_madosa_misc();
}
