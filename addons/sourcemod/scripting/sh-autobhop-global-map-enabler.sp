#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

Database g_db = null;
ConVar g_cvAutoBhop;
ConVar g_cvEnableBhop;
char g_sMapName[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
    name = "AutoBhop Enabler",
    author = ".sh",
    description = "Sets sv_autobunnyhopping based on maptiers.autobhop_enabled",
    version = "1.0",
    url = "https://surfing4fun.com"
};

public void OnPluginStart()
{
    g_cvAutoBhop = FindConVar("sv_autobunnyhopping");
    g_cvEnableBhop = FindConVar("sv_enablebunnyhopping");

    char error[256];
    g_db = SQL_Connect("default", true, error, sizeof(error));

    if (g_db == null)
    {
        SetFailState("[autobhop] Failed to connect to database: %s", error);
    }

    RegAdminCmd("sm_setautobhop", Command_SetAutoBhop, ADMFLAG_CONVARS, "Toggle autobhop_enabled for current map");
}

public void OnDatabaseConnected(Database db, const char[] error, any data)
{
    if (db == null)
    {
        SetFailState("[autobhop_enabler] DB connect failed: %s", error);
        return;
    }

    g_db = db;
    PrintToServer("[autobhop_enabler] DB connected.");
}

public void OnMapStart()
{
    if (g_db == null)
    {
        PrintToServer("[autobhop_enabler] DB not ready.");
        return;
    }

    GetCurrentMap(g_sMapName, sizeof(g_sMapName));

    char query[256];
    Format(query, sizeof(query), "SELECT autobhop_enabled FROM maptiers WHERE map = '%s' LIMIT 1;", g_sMapName);
    g_db.Query(OnBhopQueryResult, query);
}

public void OnBhopQueryResult(Database db, DBResultSet results, const char[] error, any data)
{
    if (results == null)
    {
        LogError("[autobhop_enabler] Query failed: %s", error);
        return;
    }

    if (!results.FetchRow())
    {
        PrintToServer("[autobhop_enabler] No autobhop setting found for map: %s", g_sMapName);
        return;
    }

    int enabled = results.FetchInt(0);
    g_cvAutoBhop.SetBool(enabled != 0);
    g_cvEnableBhop.SetBool(enabled != 0);

    PrintToServer("[autobhop_enabler] sv_autobunnyhopping set to %d for map: %s", enabled, g_sMapName);
}

public Action Command_SetAutoBhop(int client, int args)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }

    char query[256];
    Format(query, sizeof(query), "SELECT autobhop_enabled FROM maptiers WHERE map = '%s' LIMIT 1;", g_sMapName);

    DBResultSet results = SQL_Query(g_db, query);
    if (results == null || !results.FetchRow())
    {
        PrintToChat(client, "[autobhop_enabler] Failed to fetch current autobhop state.");
        return Plugin_Handled;
    }

    int current = results.FetchInt(0);
    int newValue = current == 0 ? 1 : 0;

    Format(query, sizeof(query), "UPDATE maptiers SET autobhop_enabled = %d WHERE map = '%s';", newValue, g_sMapName);
    if (!SQL_FastQuery(g_db, query))
    {
        PrintToChat(client, "[autobhop_enabler] Failed to update autobhop_enabled.");
        return Plugin_Handled;
    }

    g_cvAutoBhop.SetBool(newValue != 0);
    g_cvEnableBhop.SetBool(newValue != 0);

    PrintToChatAll("[autobhop_enabler] %N toggled autobhop to %d on map %s.", client, newValue, g_sMapName);
    return Plugin_Handled;
}