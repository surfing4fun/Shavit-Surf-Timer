#include <sourcemod>

#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define CREATE_TABLE_SQL "CREATE TABLE IF NOT EXISTS maps_autobhop_settings (map VARCHAR(255) NOT NULL, track INT NOT NULL, autobhop_enabled BOOLEAN NOT NULL DEFAULT FALSE, PRIMARY KEY (map, track));"

Database g_db = null;
char g_sMapName[PLATFORM_MAX_PATH];
bool gB_Auto[MAXPLAYERS + 1];

ConVar gc_AutoBhop;
ConVar gc_EnableBhop;

public Plugin myinfo = {
  name = "Track-based Autobhop",
  author = ".sh",
  description = "Handles sv_autobunnyhopping per map+track using maps_autobhop_settings database table",
  version = "1.0",
  url = "https://surfing4fun.com"
};

public void OnPluginStart() {
  InitConVars();
  if (!InitDatabase()) return;
  RegisterCommands();
}

void InitConVars() {
  gc_AutoBhop = FindConVar("sv_autobunnyhopping");
  gc_EnableBhop = FindConVar("sv_enablebunnyhopping");
}

bool InitDatabase() {
  char err[256];
  g_db = SQL_Connect("default", true, err, sizeof(err));
  if (g_db == null) {
    SetFailState("[autobhop_track] DB connect failed: %s", err);
    return false;
  }
  if (!SQL_FastQuery(g_db, CREATE_TABLE_SQL)) {
    SetFailState("[autobhop_track] Could not create settings table");
    return false;
  }
  return true;
}

void RegisterCommands() {
  RegAdminCmd("sm_setautobhoptrack", Command_SetAutoBhopTrack, ADMFLAG_GENERIC, "Usage: sm_setautobhoptrack <track>");
}

public void OnMapStart() {
  GetCurrentMap(g_sMapName, sizeof(g_sMapName));
}

public Action Command_SetAutoBhopTrack(int client, int args) {
  if (!IsClientInGame(client)) {
    return Plugin_Handled;
  }
  if (args < 1) {
    PrintToChat(client, "[autobhop_track] Usage: !setautobhoptrack <track>");
    return Plugin_Handled;
  }

  char sTrack[16];
  GetCmdArg(1, sTrack, sizeof(sTrack));
  int track = StringToInt(sTrack);

  char query[256];
  Format(query, sizeof(query),
    "SELECT autobhop_enabled FROM maps_autobhop_settings WHERE map = '%s' AND track = %d LIMIT 1;",
    g_sMapName, track);

  DBResultSet results = SQL_Query(g_db, query);
  if (results == null) {
    PrintToChat(client, "[autobhop_track] Failed to query the database.");
    return Plugin_Handled;
  }

  int newValue;
  if (results.FetchRow()) {
    int current = results.FetchInt(0);
    newValue = (current == 0) ? 1 : 0;
    Format(query, sizeof(query),
      "UPDATE maps_autobhop_settings SET autobhop_enabled = %s WHERE map = '%s' AND track = %d;",
      (newValue ? "TRUE" : "FALSE"), g_sMapName, track);
  } else {
    newValue = 1;
    Format(query, sizeof(query),
      "INSERT INTO maps_autobhop_settings (map, track, autobhop_enabled) VALUES ('%s', %d, %s);",
      g_sMapName, track, (newValue ? "TRUE" : "FALSE"));
  }

  if (!SQL_FastQuery(g_db, query)) {
    PrintToChat(client, "[autobhop_track] Failed to write to database.");
    return Plugin_Handled;
  }

  PrintToChatAll("[autobhop_track] %N set autobhop to %d for map %s track %d.", client, newValue, g_sMapName, track);
  return Plugin_Handled;
}

public void Shavit_OnTrackChanged(int client, int oldtrack, int newtrack) {
  if (!IsClientInGame(client)) {
    return;
  }

  char query[256];
  Format(query, sizeof(query),
    "SELECT autobhop_enabled FROM maps_autobhop_settings WHERE map = '%s' AND track = %d LIMIT 1;",
    g_sMapName, newtrack);

  DBResultSet results = SQL_Query(g_db, query);
  if (results == null) {
    PrintToServer("[autobhop_track] Failed to query database for track change.");
    return;
  }

  int value;
  if (results.FetchRow()) {
    value = results.FetchInt(0);
  } else {
    value = 0;
    Format(query, sizeof(query),
      "INSERT INTO maps_autobhop_settings (map, track, autobhop_enabled) VALUES ('%s', %d, %s);",
      g_sMapName, newtrack, (value ? "TRUE" : "FALSE"));
    SQL_FastQuery(g_db, query);
    PrintToServer("[autobhop_track] Inserted default autobhop_enabled = FALSE for map %s track %d", g_sMapName, newtrack);
  }

  bool autoEnabled = (value != 0);
  gB_Auto[client] = autoEnabled;
  PrintToServer("[autobhop_track] Replicated sv_autobunnyhopping = %d to %N on track %d", value, client, newtrack);
}

public Action OnPlayerRunCmd(int client, int & buttons, int & impulse, float vel[3], float angles[3], int & weapon, int & subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2]) {
  if (IsFakeClient(client)) {
    return Plugin_Continue;
  }

  MoveType mtMoveType = GetEntityMoveType(client);
  int iOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
  bool bInWater = (GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2);
  if (gB_Auto[client]) {
    if ((buttons & IN_JUMP) > 0 && mtMoveType == MOVETYPE_WALK && !bInWater) {
      gc_AutoBhop.ReplicateToClient(client, "1");
      gc_EnableBhop.ReplicateToClient(client, "1");
      SetEntProp(client, Prop_Data, "m_nOldButtons", (iOldButtons &= ~IN_JUMP));
      SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
    }
  }
  return Plugin_Continue;
}