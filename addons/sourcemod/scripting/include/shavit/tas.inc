/*
 * shavit's Timer - tas.inc file
 * by: xutaxkamay, shavit, rtldg
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#if defined _shavit_tas_included
	#endinput
#endif
#define _shavit_tas_included

enum AutostrafeOverride
{
	AutostrafeOverride_Normal, // only w/s disables autostrafe
	AutostrafeOverride_Surf, // w/s always disables, a/d only over surf ramps
	AutostrafeOverride_Surf_W_Okay, // s always disables, a/d only over surf ramps
	AutostrafeOverride_All, // all keys disable
	AutostrafeOverride_Size // size
};

enum AutostrafeType
{
	AutostrafeType_Any = -1,
	AutostrafeType_Disabled = 0,
	AutostrafeType_1Tick = 1, // xutaxkamay
	AutostrafeType_Autogain, // oblivious
	AutostrafeType_AutogainNoSpeedLoss, // oblivious
	AutostrafeType_Basic, //
	AutostrafeType_Size
};

/**
 * Sets whether the client has the autostrafe/strafehack enabled.
 *
 * @param client		Client index
 * @param value			New value to set the autostrafe/strafehack to.
 * @noreturn
 */
native void Shavit_SetAutostrafeEnabled(int client, bool value);

/**
 * Retrieves whether the client has the autostrafe/strafehack enabled.
 *
 * @param client		Client index
 * @return				The current autostrafe/strafehack enabled value.
 */
native bool Shavit_GetAutostrafeEnabled(int client);

/**
 * Sets the autostrafe/strafehack type on the given client index.
 *
 * @param client		Client index of the player to set the autostrafe/strafehack on.
 * @param value			New type to set the strafehack to.
 * @noreturn
 */
native void Shavit_SetAutostrafeType(int client, AutostrafeType value);

/**
 * Retrieves the current strafehack type for the given client index.
 *
 * @param client		Client index of the player to get the strafehack type from.
 * @return				The current strafehack type.
 */
native AutostrafeType Shavit_GetAutostrafeType(int client);

/**
 * Sets the strafehack power on the given client index. Power is the cut off point before it will turn into an autostrafe. 1.0 is the default.
 *
 * @param client		Client index of the player to set the power on.
 * @param value			New power setting.
 * @noreturn
 */
native void Shavit_SetAutostrafePower(int client, float value);

/**
 * Retrieves the current strafehack power for the given client index. Default is 1.0
 *
 * @param client		Client index of the player to get the strafehack power.
 * @return				The current strafehack power.
 */
native float Shavit_GetAutostrafePower(int client);

/**
 * Sets the key override type on the given client index.
 *
 * @param client		Client index
 * @param value			New type to set the key override to.
 * @noreturn
 */
native void Shavit_SetAutostrafeKeyOverride(int client, AutostrafeOverride value);

/**
 * Retrieves the current key override type for the given client index.
 *
 * @param client		Client index
 * @return				The current key override type.
 */
native AutostrafeOverride Shavit_GetAutostrafeKeyOverride(int client);

/**
 * Sets whether the client has automatic prestrafe enabled.
 *
 * @param client		Client index
 * @param value			New value to set the automatic prestrafe to.
 * @noreturn
 */
native void Shavit_SetAutoPrestrafe(int client, bool value);

/**
 * Retrieves whether the client has automatic prestrafe enabled.
 *
 * @param client		Client index
 * @return				The current auto prestrafe value.
 */
native bool Shavit_GetAutoPrestrafe(int client);

/**
 * Sets whether the client automatically jumps when they leave the start zone.
 *
 * @param client		Client index
 * @param value			New value to set the automatic jump to.
 * @noreturn
 */
native void Shavit_SetAutoJumpOnStart(int client, bool value);

/**
 * Retrieves whether the client automatically jumps when they leave the start zone.
 *
 * @param client		Client index
 * @return				The current auto jump value.
 */
native bool Shavit_GetAutoJumpOnStart(int client);

/**
 * Sets whether the client uses the autogain basic strafer.
 *
 * @param client		Client index
 * @param value			New value to set the autogain basic strafer to.
 * @noreturn
 */
native void Shavit_SetAutogainBasicStrafer(int client, bool value);

/**
 * Retrieves whether the client has has enabled the autogain basic strafer :tm:
 *
 * @param client		Client index
 * @return				The current autogain basic strafer setting.
 */
native bool Shavit_GetAutogainBasicStrafer(int client);

stock bool TRFilter_NoPlayers(int entity, int mask, any data)
{
	return !(1 <= entity <= MaxClients);
}


public SharedPlugin __pl_shavit_tas =
{
	name = "shavit-tas",
	file = "shavit-tas.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_tas_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_SetAutostrafeEnabled");
	MarkNativeAsOptional("Shavit_GetAutostrafeEnabled");
	MarkNativeAsOptional("Shavit_SetAutostrafeType");
	MarkNativeAsOptional("Shavit_GetAutostrafeType");
	MarkNativeAsOptional("Shavit_SetAutostrafePower");
	MarkNativeAsOptional("Shavit_GetAutostrafePower");
	MarkNativeAsOptional("Shavit_SetAutostrafeKeyOverride");
	MarkNativeAsOptional("Shavit_GetAutostrafeKeyOverride");
	MarkNativeAsOptional("Shavit_SetAutoPrestrafe");
	MarkNativeAsOptional("Shavit_GetAutoPrestrafe");
	MarkNativeAsOptional("Shavit_SetAutoJumpOnStart");
	MarkNativeAsOptional("Shavit_GetAutoJumpOnStart");
	MarkNativeAsOptional("Shavit_SetEdgeJump");
	MarkNativeAsOptional("Shavit_GetEdgeJump");
	MarkNativeAsOptional("Shavit_SetAutogainBasicStrafer");
	MarkNativeAsOptional("Shavit_GetAutogainBasicStrafer");
}
#endif
