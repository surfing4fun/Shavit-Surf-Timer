#pragma dynamic 69696
#include <sourcemod>
#include <sdktools>

ConVar g_hEnabledAutoTag;
bool g_bAutoTagEnabled;
Database g_hDashboardDB;

bool g_bClientTagged[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "Auto-Tag Subscription Users",
    author = "Sh ft. ChatGPT",
    description = "Temporarily grants Custom1 flag to users with subscription type 1 or 2.",
    version = "1.0"
};

public void OnPluginStart()
{
    g_hEnabledAutoTag = CreateConVar("enable_autotag", "1", "Enable automatic Custom1 tagging for subscribers.", FCVAR_NOTIFY);
    g_bAutoTagEnabled = g_hEnabledAutoTag.BoolValue;
    g_hEnabledAutoTag.AddChangeHook(OnAutoTagCvarChanged);

    SQL_TConnect(SQL_OnDashboardDatabaseConnected, "dashboard", 0);
}

public void SQL_OnDashboardDatabaseConnected(Handle owner, Handle hndl, const char[] error, any data)
{
    if (hndl == null)
    {
        SetFailState("[AutoTag] Failed to connect to dashboard database: %s", error);
    }

    g_hDashboardDB = view_as<Database>(hndl);
    PrintToServer("[AutoTag] Successfully connected to dashboard database.");
}

public void OnAutoTagCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_bAutoTagEnabled = StringToInt(newValue) != 0;
}

public void OnClientPostAdminCheck(int client)
{
    if (!g_bAutoTagEnabled || !IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
        return;

    g_bClientTagged[client] = false;

    if (CheckCommandAccess(client, "autotag_access", ADMFLAG_CUSTOM1, false))
    {
        // Already has Custom1, nothing to do.
        return;
    }

    if (g_hDashboardDB == null)
    {
        PrintToServer("[AutoTag] Database not connected yet. Skipping client %N.", client);
        return;
    }

    char steamId64[64];
    GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64));

    char query[512];
    Format(query, sizeof(query),
        "SELECT s.status, s.type FROM Users u JOIN Subscriptions s ON u.id = s.userId WHERE u.steamId = '%s' LIMIT 1;",
        steamId64);

    DataPack pack = new DataPack();
    pack.WriteCell(client);
    SQL_TQuery(g_hDashboardDB, SQL_CheckSubscriptionCallback, query, pack);
}

public void SQL_CheckSubscriptionCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    int client = pack.ReadCell();
    delete pack;

    if (!IsClientConnected(client) || !IsClientInGame(client))
        return;

    if (results == null)
    {
        LogError("[AutoTag] SQL query failed: %s", error);
        return;
    }

    if (results.FetchRow())
    {
        char status[32];
        results.FetchString(0, status, sizeof(status));

        char subType[32];
        results.FetchString(1, subType, sizeof(subType));

        if (StrEqual(status, "active", false) && (StrEqual(subType, "1", false) || StrEqual(subType, "2", false)))
        {
            GrantCustom1Flag(client);
        }
    }
}

void GrantCustom1Flag(int client)
{
    int flags = GetUserFlagBits(client);

    // Set Custom1 flag
    flags |= ADMFLAG_CUSTOM1;
    SetUserFlagBits(client, flags);

    g_bClientTagged[client] = true;
    PrintToServer("[AutoTag] Granted temporary Custom1 flag to %N.", client);
}

public void OnClientDisconnect(int client)
{
    if (g_bClientTagged[client])
    {
        int flags = GetUserFlagBits(client);

        // Remove Custom1 flag
        flags &= ~ADMFLAG_CUSTOM1;
        SetUserFlagBits(client, flags);

        g_bClientTagged[client] = false;
        PrintToServer("[AutoTag] Removed temporary Custom1 flag from %N.", client);
    }
}
