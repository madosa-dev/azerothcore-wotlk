#!/usr/bin/env python3
"""Turn the build specs below into addon/TalentAdvisor/Builds.lua.

The specs name talents; this resolves each name against the real tree from
Talent.dbc (dump_trees.py), so the coordinates the addon ships can never drift
from the client's trees. Every plan is then played out point by point and
rejected unless it holds up:

  * the talent exists in that class's tree
  * no talent gets more points than it has ranks
  * a talent in tier N is only taken once 5*(N-1) points sit in that tree
  * a talent with a prerequisite is only taken once the prerequisite is full
  * the plan spends exactly 71 points, one per level from 10 to 80

Run dump_trees.py first - this reads the talents.json it leaves behind.

Usage: gen_builds.py [<out file>]   (defaults to ../../addon/TalentAdvisor/Builds.lua)
"""
import json
import os
import sys

POINTS = 71          # levels 10..80
FIRST_LEVEL = 10

# --------------------------------------------------------------------------
# Stat weights
#
# One point of attack power is worth 1.0 in the physical builds and one point
# of spell power is worth 1.0 in the casting ones; everything else is relative
# to that. Scores are only ever compared inside one build, so the two anchors
# never meet. These are levelling heuristics - survivability and hit are worth
# more than they are at 80, where hit is capped and nothing hits back.
# --------------------------------------------------------------------------

W_MELEE_STR = dict(STR=2.4, AGI=1.0, STA=0.6, INT=0.0, SPI=0.0,
                   AP=1.0, CRIT=1.8, HIT=2.2, HASTE=1.4, EXP=2.0, ARP=1.1,
                   SP=0.0, MP5=0.0, ARMOR=0.02, DEF=0.2, DODGE=0.3, PARRY=0.3,
                   BLOCK=0.0, BLOCKR=0.0, RESIL=0.3, HP5=0.1,
                   DPS_MH=5.5, DPS_OH=3.0, DPS_2H=6.0, SPEED_MH=20, SPEED_2H=30)

W_MELEE_AGI = dict(STR=1.0, AGI=2.4, STA=0.5, INT=0.0, SPI=0.0,
                   AP=1.0, CRIT=1.9, HIT=2.4, HASTE=1.5, EXP=2.0, ARP=1.1,
                   SP=0.0, MP5=0.0, ARMOR=0.02, DEF=0.2, DODGE=0.4, PARRY=0.3,
                   BLOCK=0.0, BLOCKR=0.0, RESIL=0.3, HP5=0.1,
                   DPS_MH=5.5, DPS_OH=4.0, DPS_2H=5.0, SPEED_MH=15, SPEED_2H=15)

W_CASTER = dict(STR=0.0, AGI=0.0, STA=0.25, INT=0.55, SPI=0.25,
                AP=0.0, CRIT=0.9, HIT=1.2, HASTE=0.95, EXP=0.0, ARP=0.0,
                SP=1.0, MP5=0.5, ARMOR=0.01, DEF=0.1, DODGE=0.1, PARRY=0.0,
                BLOCK=0.0, BLOCKR=0.0, RESIL=0.2, HP5=0.1,
                DPS_MH=0.6, DPS_OH=0.3, DPS_2H=0.8, SPEED_MH=0, SPEED_2H=0)

W_HEAL = dict(STR=0.0, AGI=0.0, STA=0.3, INT=0.7, SPI=0.5,
              AP=0.0, CRIT=0.65, HIT=0.0, HASTE=0.75, EXP=0.0, ARP=0.0,
              SP=1.0, MP5=0.9, ARMOR=0.01, DEF=0.1, DODGE=0.1, PARRY=0.0,
              BLOCK=0.0, BLOCKR=0.0, RESIL=0.2, HP5=0.15,
              DPS_MH=0.4, DPS_OH=0.2, DPS_2H=0.5, SPEED_MH=0, SPEED_2H=0)

W_TANK = dict(STR=1.0, AGI=1.3, STA=2.6, INT=0.0, SPI=0.0,
              AP=0.25, CRIT=0.5, HIT=0.8, HASTE=0.4, EXP=1.0, ARP=0.1,
              SP=0.2, MP5=0.0, ARMOR=0.06, DEF=2.6, DODGE=2.2, PARRY=2.2,
              BLOCK=0.5, BLOCKR=1.2, RESIL=0.6, HP5=0.4,
              DPS_MH=2.5, DPS_OH=1.2, DPS_2H=2.0, SPEED_MH=0, SPEED_2H=0)


def w(base, **over):
    d = dict(base)
    d.update(over)
    return d


# --------------------------------------------------------------------------
# Builds. steps are (tab, talent name, points); a talent may appear more than
# once, which is how a plan says "two now, the third much later".
# --------------------------------------------------------------------------

BUILDS = {
'SHAMAN': {
    'default': 'enhancement',
    'builds': [
    dict(key='enhancement', name='Enhancement', role='melee', school='melee',
         desc='Dual-wield melee. The fastest solo levelling spec the class has.',
         dualWield=('talent', 'Dual Wield'), armorFloor=0.55,
         weights=w(W_MELEE_STR, STR=2.2, AGI=2.0, INT=1.1, STA=0.7, SPI=0.1,
                   CRIT=1.9, HASTE=1.3, EXP=1.8, ARP=1.0, SP=0.35, MP5=0.6,
                   ARMOR=0.03, BLOCK=0.1, DPS_2H=5.5, SPEED_MH=25, SPEED_2H=25),
         notes=[
             'Imbue: Rockbiter -> Flametongue at 10 -> Windfury on the main hand at 30. From 40 Windfury MH + Flametongue OH (Lava Lash).',
             'Shield: Lightning Shield until 20, Water Shield after.',
             'Weapons: the slowest two-hander you can find until 40, two slow one-handers after.',
             'Intellect is weighted for a melee build on purpose - Mental Quickness turns it into attack power.',
         ],
         steps=[
             (2, 'Ancestral Knowledge', 5), (2, 'Improved Ghost Wolf', 2),
             (2, 'Thundering Strikes', 5), (2, 'Shamanistic Focus', 1),
             (2, 'Improved Shields', 2), (2, 'Flurry', 5),
             (2, 'Elemental Weapons', 3), (2, 'Spirit Weapons', 1),
             (2, 'Improved Shields', 1), (2, 'Mental Dexterity', 3),
             (2, 'Weapon Mastery', 2), (2, 'Dual Wield', 1), (2, 'Stormstrike', 1),
             (2, 'Weapon Mastery', 1), (2, 'Dual Wield Specialization', 3),
             (2, 'Lava Lash', 1), (2, 'Improved Stormstrike', 2),
             (2, 'Static Shock', 1), (2, 'Shamanistic Rage', 1),
             (2, 'Mental Quickness', 3), (2, 'Static Shock', 1),
             (2, 'Maelstrom Weapon', 5), (2, 'Feral Spirit', 1),
             (2, 'Unleashed Rage', 3), (2, 'Toughness', 5), (2, 'Static Shock', 1),
             (2, 'Improved Windfury Totem', 2),
             (1, 'Concussion', 5), (1, 'Elemental Devastation', 3), (1, 'Call of Flame', 1),
         ]),

    dict(key='elemental', name='Elemental', role='caster', school='spell',
         desc='Lightning Bolt and Lava Burst from range. Kills at a distance, drinks a lot.',
         dualWield=None, armorFloor=0.55,
         weights=w(W_CASTER, INT=0.6, MP5=0.55, CRIT=1.0),
         notes=[
             'Water Shield from 20 is the mana engine - keep it up, and Improved Water Shield in the tail refills it on crits.',
             'Totems: Searing until Fire Elemental range matters, Wrath of Air / Totem of Wrath once talented.',
             'The last 13 points go into Restoration for Totemic Focus, Tidal Focus and Improved Water Shield - the mana block the raid spec uses.',
         ],
         steps=[
             (1, 'Concussion', 5), (1, 'Convection', 5), (1, 'Elemental Focus', 1),
             (1, 'Elemental Fury', 5), (1, 'Call of Flame', 3), (1, 'Elemental Warding', 3),
             (1, 'Call of Thunder', 1), (1, 'Elemental Reach', 2), (1, 'Lightning Mastery', 5),
             (1, 'Elemental Mastery', 1), (1, 'Elemental Precision', 3),
             (1, 'Storm, Earth and Fire', 3), (1, 'Elemental Oath', 2),
             (1, 'Lightning Overload', 3), (1, 'Booming Echoes', 2), (1, 'Totem of Wrath', 1),
             (1, 'Lava Flows', 3), (1, 'Astral Shift', 3), (1, 'Shamanism', 5),
             (1, 'Thunderstorm', 1),
             (3, 'Totemic Focus', 5), (3, 'Tidal Focus', 5), (3, 'Improved Water Shield', 3),
             (3, 'Improved Reincarnation', 1),
         ]),

    dict(key='restoration', name='Restoration', role='heal', school='spell',
         desc='Dungeon healer. Solo kills are slow - group up, or level Elemental and respec.',
         dualWield=None, shield=True, armorFloor=0.55,
         weights=w(W_HEAL),
         notes=[
             'Solo damage is poor with this plan. It is meant for someone healing dungeons from the teens on.',
             'Ancestral Knowledge comes first because +10% Intellect is mana and crit from level 14 on.',
             'Earth Shield at 65 and Riptide at 73 are the two points where the spec changes how it plays.',
             'The Enhancement tail buys Elemental Weapons, which is a straight +Earthliving buff.',
         ],
         steps=[
             (2, 'Ancestral Knowledge', 5),
             (3, 'Improved Healing Wave', 5), (3, 'Totemic Focus', 5), (3, 'Tidal Focus', 5),
             (3, 'Healing Focus', 3), (3, 'Improved Water Shield', 3), (3, 'Tidal Force', 1),
             (3, 'Tidal Mastery', 5), (3, 'Restorative Totems', 3), (3, 'Healing Way', 3),
             (3, "Nature's Swiftness", 1), (3, 'Purification', 5), (3, 'Mana Tide Totem', 1),
             (3, 'Blessing of the Eternals', 2), (3, "Nature's Blessing", 3),
             (3, 'Improved Chain Heal', 2), (3, 'Ancestral Awakening', 3), (3, 'Earth Shield', 1),
             (3, 'Improved Earth Shield', 2), (3, 'Tidal Waves', 5), (3, 'Riptide', 1),
             (2, 'Improved Shields', 3), (2, 'Guardian Totems', 2), (2, 'Elemental Weapons', 2),
         ]),

    dict(key='tank', name='Earthwarden', role='tank', school='melee', meta=True,
         desc='Meta build: shield, Toughness, Anticipation and Shamanistic Rage. Holds five-mans, not raids.',
         dualWield=None, shield=True, armorFloor=0.6,
         weights=w(W_TANK, DEF=1.6, BLOCKR=0.3, BLOCK=0.2, INT=0.5, SP=0.3, MP5=0.3),
         notes=[
             'A shaman cannot reach crit immunity - this holds normal five-mans, not raid bosses.',
             'Shield in the off hand at all times, Rockbiter on the weapon, Lightning Shield up for threat.',
             'Stoneclaw Totem with Guardian Totems is the panic button; Shamanistic Rage at 54 is the real cooldown.',
             'Maelstrom Weapon plus instant Healing Wave is how the build stays alive once mobs hit harder.',
         ],
         steps=[
             (2, 'Enhancing Totems', 3), (2, "Earth's Grasp", 2), (2, 'Thundering Strikes', 5),
             (2, 'Improved Shields', 3), (2, 'Guardian Totems', 2), (2, 'Anticipation', 3),
             (2, 'Toughness', 5), (2, 'Flurry', 5), (2, 'Elemental Weapons', 3),
             (2, 'Shamanistic Focus', 1), (2, 'Weapon Mastery', 3), (2, 'Stormstrike', 1),
             (2, 'Improved Stormstrike', 2), (2, 'Static Shock', 3), (2, 'Unleashed Rage', 3),
             (2, 'Shamanistic Rage', 1), (2, 'Earthen Power', 2), (2, 'Maelstrom Weapon', 5),
             (2, 'Feral Spirit', 1),
             (3, 'Improved Healing Wave', 5), (3, 'Totemic Focus', 5), (3, 'Healing Focus', 3),
             (3, 'Ancestral Healing', 3), (3, 'Improved Water Shield', 2),
         ]),
    ]},

'WARRIOR': {
    'default': 'arms',
    'builds': [
    dict(key='arms', name='Arms', role='melee', school='melee',
         desc='Two-hander, Mortal Strike, big Overpower and Slam hits. The standard levelling spec.',
         dualWield=None, armorFloor=0.55,
         weights=w(W_MELEE_STR),
         notes=[
             'Tier 5 is a weapon specialisation - the plan takes Poleaxe (axes and polearms). Move those 5 points to Sword or Mace Specialisation if that is what you swing.',
             'Mortal Strike lands at 40, Bladestorm at 62.',
             'The last 14 points are the Fury opener block: Armored to the Teeth, Cruelty, Unbridled Wrath.',
             'Rage is the limit while levelling - Improved Charge and Improved Heroic Strike come first for that reason.',
         ],
         steps=[
             (1, 'Improved Heroic Strike', 3), (1, 'Improved Rend', 2), (1, 'Improved Charge', 2),
             (1, 'Tactical Mastery', 3), (1, 'Impale', 2), (1, 'Deep Wounds', 3),
             (1, 'Two-Handed Weapon Specialization', 3), (1, 'Taste for Blood', 3),
             (1, 'Poleaxe Specialization', 5), (1, 'Sweeping Strikes', 1),
             (1, 'Weapon Mastery', 2), (1, 'Anger Management', 1), (1, 'Mortal Strike', 1),
             (1, 'Improved Slam', 2), (1, 'Strength of Arms', 2), (1, 'Improved Mortal Strike', 3),
             (1, 'Juggernaut', 1), (1, 'Unrelenting Assault', 2), (1, 'Sudden Death', 3),
             (1, 'Endless Rage', 1), (1, 'Blood Frenzy', 2), (1, 'Wrecking Crew', 5),
             (1, 'Bladestorm', 1), (1, 'Trauma', 2), (1, 'Second Wind', 2),
             (2, 'Armored to the Teeth', 3), (2, 'Cruelty', 5), (2, 'Unbridled Wrath', 5),
             (2, 'Booming Voice', 1),
         ]),

    dict(key='fury', name='Fury', role='melee', school='melee',
         desc='Dual wield, Bloodthirst, and two two-handers at 66 with Titan\'s Grip.',
         dualWield=('level', 20), armorFloor=0.55,
         weights=w(W_MELEE_STR, HIT=2.6, CRIT=1.9, HASTE=1.5, DPS_OH=3.5),
         notes=[
             'Dual wield opens at 20 from the trainer, not from a talent - the gear advice starts pairing one-handers there.',
             "Titan's Grip at 66 flips the advice back to two-handers: from then on two of them, one in each hand.",
             'Hit rating matters more here than for any other warrior build - two weapons miss twice.',
             'The 14-point Arms tail is Deep Wounds and the rage talents, not Mortal Strike.',
         ],
         steps=[
             (2, 'Armored to the Teeth', 3), (2, 'Cruelty', 5), (2, 'Unbridled Wrath', 5),
             (2, 'Commanding Presence', 5), (2, 'Dual Wield Specialization', 5), (2, 'Enrage', 5),
             (2, 'Improved Execute', 2), (2, 'Precision', 3), (2, 'Death Wish', 1),
             (2, 'Flurry', 5), (2, 'Intensify Rage', 3), (2, 'Bloodthirst', 1),
             (2, 'Improved Berserker Stance', 5), (2, 'Bloodsurge', 3), (2, 'Unending Fury', 5),
             (2, "Titan's Grip", 1),
             (1, 'Improved Heroic Strike', 3), (1, 'Improved Rend', 2), (1, 'Tactical Mastery', 3),
             (1, 'Improved Charge', 2), (1, 'Impale', 2), (1, 'Deep Wounds', 2),
         ]),

    dict(key='protection', name='Protection', role='tank', school='melee',
         desc='Shield tank. Instant dungeon queues from the teens on, slow solo kills.',
         dualWield=None, shield=True, armorFloor=0.6,
         weights=w(W_TANK),
         notes=[
             'Shield and a one-hander at all times - the gear advice will not offer a two-hander for this build.',
             'Defense rating is the most valuable stat on an item until 540 defense at 80; it is weighted that way here.',
             'Devastate at 51 and Shockwave at 61 are the threat breakpoints.',
             'Solo damage is low - this build assumes you are tanking groups.',
         ],
         steps=[
             (3, 'Improved Bloodrage', 2), (3, 'Shield Specialization', 5),
             (3, 'Improved Thunder Clap', 3), (3, 'Anticipation', 5), (3, 'Incite', 3),
             (3, 'Toughness', 5), (3, 'Improved Revenge', 2), (3, 'Last Stand', 1),
             (3, 'Shield Mastery', 2), (3, 'Concussion Blow', 1),
             (3, 'One-Handed Weapon Specialization', 5), (3, 'Vigilance', 1),
             (3, 'Focused Rage', 3), (3, 'Vitality', 3), (3, 'Devastate', 1),
             (3, 'Warbringer', 1), (3, 'Critical Block', 3), (3, 'Sword and Board', 3),
             (3, 'Damage Shield', 2), (3, 'Shockwave', 1),
             (2, 'Armored to the Teeth', 3),
             (1, 'Improved Heroic Strike', 3), (1, 'Deflection', 5), (1, 'Improved Rend', 2),
             (1, 'Tactical Mastery', 3), (1, 'Iron Will', 3),
         ]),

    dict(key='gladiator', name='Gladiator', role='melee', school='melee', meta=True,
         desc='Meta build: damage with a shield up. Deep Wounds and Rend early, Sword and Board late.',
         dualWield=None, shield=True, armorFloor=0.55,
         weights=w(W_MELEE_STR, STA=1.2, ARMOR=0.03, BLOCK=0.8, BLOCKR=0.6,
                   DEF=0.8, DODGE=0.8, PARRY=0.8),
         notes=[
             'Arms damage talents first, the Protection half from 30 - so it plays like Arms with a shield for the first twenty levels.',
             'Devastate only lands at 72; until then Sunder Armor and Revenge carry the shield half.',
             'Block value is weighted because Shield Slam scales with it.',
             'Slower to kill than Arms, far harder to kill. Good for pulling several mobs at once.',
         ],
         steps=[
             (1, 'Improved Heroic Strike', 3), (1, 'Improved Rend', 2), (1, 'Tactical Mastery', 3),
             (1, 'Improved Charge', 2), (1, 'Impale', 2), (1, 'Deep Wounds', 3),
             (1, 'Anger Management', 1), (1, 'Taste for Blood', 3), (1, 'Improved Overpower', 1),
             (3, 'Improved Bloodrage', 2), (3, 'Shield Specialization', 5),
             (3, 'Improved Thunder Clap', 3), (3, 'Anticipation', 5), (3, 'Incite', 3),
             (3, 'Toughness', 5), (3, 'Improved Revenge', 2), (3, 'Shield Mastery', 2),
             (3, 'Concussion Blow', 1), (3, 'One-Handed Weapon Specialization', 5),
             (3, 'Focused Rage', 3), (3, 'Vitality', 3), (3, 'Puncture', 3),
             (3, 'Devastate', 1), (3, 'Critical Block', 3), (3, 'Sword and Board', 3),
             (3, 'Damage Shield', 2),
         ]),
    ]},

'PALADIN': {
    'default': 'retribution',
    'builds': [
    dict(key='retribution', name='Retribution', role='melee', school='melee',
         desc='Two-handed melee with seals and judgements. The fast way to 80.',
         dualWield=None, armorFloor=0.55,
         weights=w(W_MELEE_STR, INT=0.3, SP=0.25, MP5=0.3),
         notes=[
             'Seals of the Pure first: it is a straight damage increase from level 10 on every seal you own.',
             'Mana is the limit until Judgements of the Wise at 48; Blessing of Wisdom on yourself until then.',
             'Crusader Strike only arrives at 57 - the tree gates it behind 40 points. Until then it is Judgement and Seal procs.',
             'A little Intellect and spell power is weighted in because seals and judgements scale with both.',
         ],
         steps=[
             (1, 'Seals of the Pure', 5),
             (3, 'Benediction', 5), (3, 'Heart of the Crusader', 3), (3, 'Improved Judgements', 2),
             (3, 'Conviction', 5), (3, 'Seal of Command', 1), (3, 'Pursuit of Justice', 2),
             (3, 'Crusade', 3), (3, 'Sanctity of Battle', 3),
             (3, 'Two-Handed Weapon Specialization', 3), (3, 'Sanctified Retribution', 1),
             (3, 'Vengeance', 3), (3, 'Judgements of the Wise', 3), (3, 'The Art of War', 2),
             (3, 'Repentance', 1), (3, 'Fanaticism', 3), (3, 'Sanctified Wrath', 2),
             (3, 'Crusader Strike', 1), (3, 'Sheath of Light', 3), (3, 'Swift Retribution', 3),
             (3, 'Righteous Vengeance', 3), (3, 'Divine Storm', 1),
             (3, 'Improved Blessing of Might', 2), (3, 'Vindication', 2), (3, 'Divine Purpose', 2),
             (2, 'Divine Strength', 5),
             (1, 'Divine Intellect', 2),
         ]),

    dict(key='holy', name='Holy', role='heal', school='spell',
         desc='Plate healer. Holy Shock at 42, Beacon of Light at 61.',
         dualWield=None, shield=True, armorFloor=0.6,
         weights=w(W_HEAL, INT=0.85, MP5=0.7, SPI=0.2, ARMOR=0.02),
         notes=[
             'Intellect is weighted above Spirit: Illumination and Holy Guidance both key off it, Spirit does almost nothing for a paladin.',
             'One-hander and a shield - the gear advice will not offer a two-hander for this build.',
             'Holy Shock at 42 is the first point the spec feels different; Beacon of Light at 61 is the second.',
             'Solo damage is poor. This plan assumes you are healing groups.',
         ],
         steps=[
             (1, 'Spiritual Focus', 5), (1, 'Divine Intellect', 5), (1, 'Healing Light', 3),
             (1, 'Improved Lay on Hands', 2), (1, 'Illumination', 5),
             (1, 'Improved Blessing of Wisdom', 2), (1, 'Divine Favor', 1),
             (1, 'Sanctified Light', 3), (1, 'Aura Mastery', 1), (1, 'Holy Power', 5),
             (1, "Light's Grace", 3), (1, 'Holy Shock', 1), (1, 'Holy Guidance', 5),
             (1, 'Sacred Cleansing', 3), (1, 'Divine Illumination', 1),
             (1, 'Judgements of the Pure', 5), (1, 'Infusion of Light', 2),
             (1, 'Enlightened Judgements', 2), (1, 'Beacon of Light', 1),
             (2, 'Divinity', 5), (2, 'Anticipation', 5), (2, "Guardian's Favor", 2),
             (2, 'Improved Righteous Fury', 3), (2, 'Divine Sacrifice', 1),
         ]),

    dict(key='protection', name='Protection', role='tank', school='melee',
         desc='Plate shield tank with Avenger\'s Shield and Consecration. Holds anything.',
         dualWield=None, shield=True, armorFloor=0.6,
         weights=w(W_TANK, INT=0.5, SP=0.5, MP5=0.2),
         notes=[
             'Intellect and spell power carry real weight here - Touched by the Light and Holy Shield mean threat scales with both.',
             'Shield and a one-hander at all times.',
             'Holy Shield at 46 and Avenger\'s Shield at 59 are the two threat breakpoints; before those, Consecration and Righteous Fury do the work.',
             'Defense rating is the top armour stat until 540 defense at 80.',
         ],
         steps=[
             (2, 'Divine Strength', 5), (2, 'Anticipation', 5), (2, 'Toughness', 5),
             (2, 'Improved Righteous Fury', 3), (2, 'Divinity', 5),
             (2, 'Blessing of Sanctuary', 1), (2, 'Reckoning', 5), (2, 'Sacred Duty', 2),
             (2, 'One-Handed Weapon Specialization', 3), (2, 'Spiritual Attunement', 2),
             (2, 'Holy Shield', 1), (2, 'Ardent Defender', 3), (2, 'Redoubt', 3),
             (2, 'Combat Expertise', 3), (2, 'Touched by the Light', 3),
             (2, "Avenger's Shield", 1), (2, 'Shield of the Templar', 3),
             (2, 'Hammer of the Righteous', 1),
             (3, 'Benediction', 5), (3, 'Improved Judgements', 2),
             (3, 'Heart of the Crusader', 3), (3, 'Conviction', 5), (3, 'Pursuit of Justice', 2),
         ]),

    dict(key='shockadin', name='Shockadin', role='caster', school='spell', meta=True,
         desc='Meta build: Holy Shock as a damage spell, in plate, with a shield. Odd and effective.',
         dualWield=None, shield=True, armorFloor=0.6,
         weights=w(W_CASTER, INT=0.7, SPI=0.15, MP5=0.6, STA=0.4, ARMOR=0.02),
         notes=[
             'Holy Shock at 42 is the point the build starts working. Before that it plays like a slow Retribution.',
             'Conviction in the Retribution tail raises spell crit as well as melee crit - that is why 20 points go there.',
             'Judgement of Light plus Seal of Righteousness keeps mana and health up between shocks.',
             'Spell power plate barely exists while levelling - mail and even a caster shield are fine, the armour floor allows anything at or above mail.',
         ],
         steps=[
             (1, 'Seals of the Pure', 5), (1, 'Spiritual Focus', 5), (1, 'Divine Intellect', 5),
             (1, 'Improved Lay on Hands', 2), (1, 'Illumination', 5), (1, 'Divine Favor', 1),
             (1, 'Sanctified Light', 3), (1, 'Aura Mastery', 1), (1, 'Holy Power', 5),
             (1, "Light's Grace", 3), (1, 'Holy Shock', 1), (1, 'Holy Guidance', 5),
             (1, 'Judgements of the Pure', 5), (1, 'Blessed Life', 3),
             (1, 'Infusion of Light', 2), (1, 'Enlightened Judgements', 2),
             (1, 'Beacon of Light', 1),
             (3, 'Benediction', 5), (3, 'Improved Judgements', 2),
             (3, 'Heart of the Crusader', 3), (3, 'Conviction', 5), (3, 'Pursuit of Justice', 2),
         ]),
    ]},

'ROGUE': {
    'default': 'combat',
    'builds': [
    dict(key='combat', name='Combat', role='melee', school='melee',
         desc='Sinister Strike with two one-handers. Steady, forgiving, good with any weapon.',
         dualWield=('always',), armorFloor=0.55,
         weights=w(W_MELEE_AGI),
         notes=[
             'Tier 5 takes Hack and Slash (swords and axes). Move those 5 points to Mace Specialisation if you swing maces.',
             'A slow main hand and a fast off hand: Sinister Strike scales with main-hand damage, Combat Potency with off-hand swings.',
             'Killing Spree at 60 and Adrenaline Rush at 45 are the two cooldowns the build is built around.',
             'The single point in Nerves of Steel is the flex point - Improved Kick or Endurance work just as well there.',
         ],
         steps=[
             (2, 'Improved Sinister Strike', 2), (2, 'Dual Wield Specialization', 5),
             (2, 'Precision', 5), (2, 'Improved Slice and Dice', 2), (2, 'Endurance', 2),
             (2, 'Lightning Reflexes', 3), (2, 'Aggression', 5), (2, 'Blade Flurry', 1),
             (2, 'Hack and Slash', 5), (2, 'Weapon Expertise', 2), (2, 'Vitality', 3),
             (2, 'Adrenaline Rush', 1), (2, 'Nerves of Steel', 1), (2, 'Combat Potency', 5),
             (2, 'Surprise Attacks', 1), (2, 'Savage Combat', 2), (2, 'Prey on the Weak', 5),
             (2, 'Killing Spree', 1),
             (1, 'Malice', 5), (1, 'Remorseless Attacks', 2), (1, 'Ruthlessness', 3),
             (1, 'Lethality', 5),
             (3, 'Relentless Strikes', 5),
         ]),

    dict(key='assassination', name='Assassination', role='melee', school='melee',
         desc='Daggers and poisons. Mutilate at 54; before that it is Sinister Strike like everyone else.',
         dualWield=('always',), armorFloor=0.55,
         weights=w(W_MELEE_AGI, CRIT=2.1, HIT=2.5, DPS_MH=5.0, DPS_OH=4.5,
                   SPEED_MH=0, SPEED_2H=0),
         notes=[
             'Daggers in both hands - the plan is built on Puncturing Wounds and Mutilate, both dagger-only.',
             'Weapon speed is not weighted: for daggers the item budget matters, not the swing timer.',
             'Mutilate needs 40 points in the tree, so it lands at 54. Until then the build levels on Sinister Strike and poisons.',
             'Instant Poison main hand, Deadly Poison off hand, from the moment you can buy them.',
         ],
         steps=[
             (1, 'Malice', 5), (1, 'Ruthlessness', 3), (1, 'Puncturing Wounds', 3),
             (1, 'Lethality', 5), (1, 'Vigor', 1), (1, 'Improved Poisons', 5),
             (1, 'Vile Poisons', 3), (1, 'Cold Blood', 1), (1, 'Seal Fate', 5),
             (1, 'Overkill', 1), (1, 'Deadened Nerves', 3), (1, 'Focused Attacks', 3),
             (1, 'Find Weakness', 3), (1, 'Master Poisoner', 3), (1, 'Mutilate', 1),
             (1, 'Cut to the Chase', 5), (1, 'Hunger For Blood', 1),
             (2, 'Dual Wield Specialization', 5), (2, 'Precision', 5),
             (2, 'Close Quarters Combat', 5), (2, 'Improved Slice and Dice', 2),
             (2, 'Lightning Reflexes', 1),
             (3, 'Opportunity', 2),
         ]),

    dict(key='subtlety', name='Subtlety', role='melee', school='melee',
         desc='Openers, Hemorrhage and Shadowstep. Strong when you pick the fight, fragile when you do not.',
         dualWield=('always',), armorFloor=0.55,
         weights=w(W_MELEE_AGI, CRIT=2.0, ARP=1.3, HASTE=1.2),
         notes=[
             'Hemorrhage at 31 replaces Sinister Strike as the filler and is cheaper on energy.',
             'Master of Subtlety and Initiative reward opening from stealth on every pull - this build wants you to restealth between mobs.',
             'Shadowstep at 57 and Shadow Dance at 63 turn it into the ganking spec proper.',
             'Armor penetration is weighted higher here because Hemorrhage and Backstab are pure weapon damage.',
         ],
         steps=[
             (3, 'Relentless Strikes', 5), (3, 'Opportunity', 2), (3, 'Camouflage', 3),
             (3, 'Serrated Blades', 3), (3, 'Ghostly Strike', 1), (3, 'Elusiveness', 2),
             (3, 'Initiative', 3), (3, 'Improved Ambush', 2), (3, 'Hemorrhage', 1),
             (3, 'Dirty Deeds', 2), (3, 'Preparation', 1), (3, 'Master of Subtlety', 3),
             (3, 'Deadliness', 5), (3, 'Premeditation', 1), (3, 'Cheat Death', 3),
             (3, 'Sinister Calling', 5), (3, 'Waylay', 2), (3, 'Honor Among Thieves', 3),
             (3, 'Shadowstep', 1), (3, 'Slaughter from the Shadows', 5), (3, 'Shadow Dance', 1),
             (1, 'Malice', 5), (1, 'Ruthlessness', 3), (1, 'Puncturing Wounds', 3),
             (1, 'Lethality', 5), (1, 'Vigor', 1),
         ]),

    dict(key='riposte', name='Riposte', role='tank', school='melee', meta=True,
         desc='Meta build: parry, Riposte and Vitality in leather. Tanks five-mans nothing else will let a rogue tank.',
         dualWield=('always',), armorFloor=0.5,
         weights=w(W_TANK, AGI=2.6, STR=0.8, STA=2.2, DEF=1.4, DODGE=2.4, PARRY=2.6,
                   BLOCK=0.0, BLOCKR=0.0, ARMOR=0.05, AP=0.5, CRIT=1.0, HIT=1.4,
                   EXP=1.2, DPS_MH=3.5, DPS_OH=2.5),
         notes=[
             'A rogue has no taunt and no block. This holds five-mans through crowd control and Feint, and it dies to anything that hits back hard.',
             'Riposte at 25 needs a parry to fire - Deflection first, always face the mob.',
             'Agility is doubly weighted: dodge and crit come off the same stat, and Vitality adds 4% on top.',
             'Evasion, Cloak of Shadows, Feint and Sprint are the cooldown rotation. Use Tricks of the Trade on nobody - you are the tank.',
         ],
         steps=[
             (2, 'Improved Sinister Strike', 2), (2, 'Dual Wield Specialization', 5),
             (2, 'Deflection', 3), (2, 'Precision', 5), (2, 'Riposte', 1), (2, 'Endurance', 2),
             (2, 'Lightning Reflexes', 3), (2, 'Aggression', 5), (2, 'Blade Flurry', 1),
             (2, 'Hack and Slash', 5), (2, 'Blade Twisting', 2), (2, 'Weapon Expertise', 2),
             (2, 'Vitality', 3), (2, 'Adrenaline Rush', 1), (2, 'Nerves of Steel', 2),
             (2, 'Improved Slice and Dice', 2), (2, 'Combat Potency', 5),
             (2, 'Surprise Attacks', 1), (2, 'Savage Combat', 2), (2, 'Prey on the Weak', 5),
             (2, 'Killing Spree', 1),
             (1, 'Malice', 5), (1, 'Remorseless Attacks', 2), (1, 'Ruthlessness', 3),
             (1, 'Improved Expose Armor', 2), (1, 'Vigor', 1),
         ]),
    ]},
}


# --------------------------------------------------------------------------

class Broken(Exception):
    pass


def index(tree):
    """{(tab, name): talent} plus a per-tab name check."""
    out = {}
    for tab, data in tree.items():
        for e in data['talents']:
            out[(int(tab), e['name'])] = e
    return out


def validate(cls, build, tree):
    by_name = index(tree)
    spent = {1: 0, 2: 0, 3: 0}
    ranks = {}
    total = 0
    placed = []
    for tab, name, points in build['steps']:
        talent = by_name.get((tab, name))
        if talent is None:
            raise Broken('%s/%s: no talent "%s" in tab %d' % (cls, build['key'], name, tab))
        key = (tab, talent['tier'], talent['col'])
        for _ in range(points):
            total += 1
            have = ranks.get(key, 0)
            if have >= talent['max']:
                raise Broken('%s/%s: %s gets rank %d of %d'
                             % (cls, build['key'], name, have + 1, talent['max']))
            gate = 5 * (talent['tier'] - 1)
            if spent[tab] < gate:
                raise Broken('%s/%s: %s (tier %d) at level %d with %d points in tab %d, needs %d'
                             % (cls, build['key'], name, talent['tier'],
                                FIRST_LEVEL + total - 1, spent[tab], tab, gate))
            for p in talent['prereq']:
                pkey = (p['tab'], p['tier'], p['col'])
                if ranks.get(pkey, 0) < p['rank']:
                    raise Broken('%s/%s: %s needs %s %d/%d first (has %d) at level %d'
                                 % (cls, build['key'], name, p['name'], p['rank'], p['rank'],
                                    ranks.get(pkey, 0), FIRST_LEVEL + total - 1))
            ranks[key] = have + 1
            spent[tab] += 1
            placed.append((FIRST_LEVEL + total - 1, tab, talent, ranks[key]))
    if total != POINTS:
        raise Broken('%s/%s: %d points, expected %d' % (cls, build['key'], total, POINTS))
    return placed, spent


def resolve_coord(tree, tab, name):
    for e in tree[tab]['talents'] if isinstance(tab, int) else []:
        if e['name'] == name:
            return e
    return None


def emit(cls, build, tree, placed, spent):
    by_name = index(tree)
    lines = []
    lines.append('        %s = {' % build['key'])
    lines.append('            name = %s,' % lua_str(build['name']))
    lines.append('            role = %s,' % lua_str(build['role']))
    lines.append('            school = %s,' % lua_str(build['school']))
    lines.append('            desc = %s,' % lua_str(build['desc']))
    if build.get('meta'):
        lines.append('            meta = true,')
    if build.get('shield'):
        lines.append('            shield = true,')
    lines.append('            armorFloor = %s,' % build['armorFloor'])
    dw = build.get('dualWield')
    if dw and dw[0] == 'always':
        lines.append('            dualWield = true,')
    elif dw and dw[0] == 'level':
        lines.append('            dualWield = { level = %d },' % dw[1])
    elif dw and dw[0] == 'talent':
        t = by_name[(2, dw[1])] if (2, dw[1]) in by_name else None
        if t is None:
            raise Broken('%s/%s: dual wield talent "%s" not found' % (cls, build['key'], dw[1]))
        lines.append('            dualWield = { tab = 2, tier = %d, col = %d }, -- %s'
                     % (t['tier'], t['col'], dw[1]))
    lines.append('            spent = { %d, %d, %d },'
                 % (spent[1], spent[2], spent[3]))

    lines.append('')
    lines.append('            -- {tab, tier, col, points}. %d points, levels %d-%d.'
                 % (POINTS, FIRST_LEVEL, FIRST_LEVEL + POINTS - 1))
    lines.append('            steps = {')
    level = FIRST_LEVEL
    for tab, name, points in build['steps']:
        t = by_name[(tab, name)]
        span = ('%d' % level) if points == 1 else ('%d-%d' % (level, level + points - 1))
        lines.append('                { %d, %2d, %d, %d }, -- %-7s %s'
                     % (tab, t['tier'], t['col'], points, span, name))
        level += points
    lines.append('            },')

    lines.append('')
    lines.append('            weights = {')
    order = ['STR', 'AGI', 'STA', 'INT', 'SPI', 'AP', 'SP', 'CRIT', 'HIT', 'HASTE',
             'EXP', 'ARP', 'MP5', 'HP5', 'ARMOR', 'DEF', 'DODGE', 'PARRY', 'BLOCK',
             'BLOCKR', 'RESIL', 'DPS_MH', 'DPS_OH', 'DPS_2H', 'SPEED_MH', 'SPEED_2H']
    row = []
    for i, stat in enumerate(order):
        row.append('%s = %s,' % (stat, fmt(build['weights'][stat])))
        if len(row) == 5 or i == len(order) - 1:
            lines.append('                ' + ' '.join(row))
            row = []
    lines.append('            },')

    lines.append('')
    lines.append('            notes = {')
    for n in build['notes']:
        lines.append('                %s,' % lua_str(n))
    lines.append('            },')
    lines.append('        },')
    return lines


def fmt(v):
    if v == int(v):
        return str(int(v))
    return ('%.2f' % v).rstrip('0')


def lua_str(s):
    return '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')


HEADER = '''-- TalentAdvisor builds: the data Core.lua advises from.
--
-- GENERATED by tools/talentadvisor/gen_builds.py from Talent.dbc. Edit the
-- specs there and regenerate; hand edits here are lost and, worse, unchecked.
--
-- A build is an ordered list of steps. Each step names a talent by its place
-- in the tree - tab index, tier, column, all 1-based exactly as
-- GetTalentInfo() reports them - and how many points go there before the plan
-- moves on. The same talent may appear more than once (Improved Shields gets
-- two points early and its third much later), which is what lets a plan say
-- "come back to this" instead of forcing every talent to be filled in one go.
--
-- Position is used instead of names on purpose: names are localised, tiers
-- and columns are not, so a plan written here works on any client language.
-- The names in the trailing comments are for whoever reads this file; the
-- names the addon shows are read live from the game.
--
-- The tab order is the order the trees appear in the talent window
-- (TalentTab.dbc OrderIndex).
--
-- role decides which group the build appears under in the picker, and is what
-- the "what do you want to play" question is asking. school is what a rating
-- with no school on it ("+8 critical strike rating") is taken to mean, so a
-- caster build does not count melee-only ratings and the other way round.
--
-- weights: how many "points" one unit of a stat is worth when ranking gear.
-- Attack power is 1.0 in the physical builds, spell power 1.0 in the casting
-- ones; scores are only ever compared inside one build so the two anchors
-- never meet. Weapon damage is rated per DPS and per hand (DPS_MH, DPS_OH,
-- DPS_2H), and slow weapons get SPEED_MH / SPEED_2H per second of speed above
-- 2.0. These are levelling heuristics, not raid-sim output; /ta weights lists
-- them.
--
-- armorFloor: an armour piece scoring well is still rejected if its armour is
-- below this fraction of what is worn in that slot - that is what stops a
-- healer in plate being told to put on a cloth robe with more Intellect.
--
-- shield: the build fights with something in the off hand, so no two-hander is
-- ever suggested. dualWield says when two one-handers may be paired: true
-- always, { level = n } from that level, { tab, tier, col } once that talent
-- is taken, absent never.

TalentAdvisorBuilds = {
'''


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        here, '..', '..', 'addon', 'TalentAdvisor', 'Builds.lua')
    trees = json.load(open(os.path.join(here, 'talents.json')))

    body = []
    for cls in sorted(BUILDS):
        tree = {int(k): v for k, v in trees[cls].items()}
        body.append('    %s = {' % cls)
        body.append('        default = %s,' % lua_str(BUILDS[cls]['default']))
        body.append('')
        for build in BUILDS[cls]['builds']:
            placed, spent = validate(cls, build, tree)
            body.extend(emit(cls, build, tree, placed, spent))
            print('%-8s %-14s %-7s %s  %s' % (
                cls, build['key'], build['role'],
                '/'.join(str(spent[t]) for t in (1, 2, 3)),
                'meta' if build.get('meta') else ''))
        body.append('    },')
        body.append('')
    open(out_path, 'w').write(HEADER + '\n'.join(body).rstrip() + '\n}\n')
    print('\nwrote %s' % os.path.relpath(out_path, here))


if __name__ == '__main__':
    main()
