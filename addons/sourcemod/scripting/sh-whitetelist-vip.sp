#pragma dynamic 69696
#include <sourcemod>
#include <sdktools>

ConVar g_hEnabledWhitelist;
bool g_bWhitelistEnabled;
Database g_hDashboardDB;

bool g_bClientAuthorized[MAXPLAYERS + 1];
char g_sClientSubscriptionType[MAXPLAYERS + 1][32];

Handle g_hHostnameTimer = INVALID_HANDLE;

public Plugin myinfo =
{
    name = "Simple VIP Whitelist with Subscription Check",
    author = "Sh ft. ChatGPT",
    description = "Allows players with Custom1 flag or active subscription type 2 (whitelist) in dashboard database.",
    version = "1.0"
};

public void OnPluginStart()
{
    g_hEnabledWhitelist = CreateConVar("enabledwhitelist", "0", "Enable whitelist based on Custom1 flag or subscription", FCVAR_NOTIFY);
    g_hEnabledWhitelist.AddChangeHook(OnWhitelistCvarChanged);

    g_bWhitelistEnabled = g_hEnabledWhitelist.BoolValue;

    if (g_bWhitelistEnabled)
    {
        PrintToServer("[Whitelist] Plugin active. Only Custom1 or valid whitelist subscription allowed.");
    }
    else
    {
        PrintToServer("[Whitelist] Whitelist disabled. Anyone can join.");
    }

    SQL_TConnect(SQL_OnDashboardDatabaseConnected, "dashboard", 0);
}

public void OnMapStart()
{
    if (g_hHostnameTimer != INVALID_HANDLE)
    {
        KillTimer(g_hHostnameTimer);
    }
    g_hHostnameTimer = CreateTimer(10.0, Timer_UpdateHostname, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_UpdateHostname(Handle timer)
{
    UpdateHostname();
    g_hHostnameTimer = INVALID_HANDLE;
    return Plugin_Stop;
}

public void SQL_OnDashboardDatabaseConnected(Handle owner, Handle hndl, const char[] error, any data)
{
    if (hndl == null)
    {
        SetFailState("[Whitelist] Failed to connect to dashboard database: %s", error);
    }

    g_hDashboardDB = view_as<Database>(hndl);
    PrintToServer("[Whitelist] Successfully connected to dashboard database.");
}

public void OnWhitelistCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_bWhitelistEnabled = StringToInt(newValue) != 0;

    if (g_bWhitelistEnabled)
    {
        PrintToServer("[Whitelist] Whitelist ENABLED. Only Custom1 or valid whitelist subscription allowed.");
    }
    else
    {
        PrintToServer("[Whitelist] Whitelist DISABLED. Anyone can join.");
    }
    UpdateHostname();
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsClientConnected(client) || !IsClientInGame(client))
        return;

    if (IsFakeClient(client))
        return;

    g_bClientAuthorized[client] = false;
    g_sClientSubscriptionType[client][0] = '\0';

    if (!g_bWhitelistEnabled)
    {
        g_bClientAuthorized[client] = true;
        return;
    }

    if (CheckCommandAccess(client, "whitelist_access", ADMFLAG_CUSTOM1, false))
    {
        g_bClientAuthorized[client] = true;
        return;
    }

    if (g_hDashboardDB == null)
    {
        PrintToServer("[Whitelist] Database not connected yet. Allowing client %N.", client);
        g_bClientAuthorized[client] = true;
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
        LogError("[Whitelist] SQL query failed: %s", error);
        g_bClientAuthorized[client] = false;
        EvaluateClientAuthorization(client);
        return;
    }

    if (results.FetchRow())
    {
        char status[32];
        results.FetchString(0, status, sizeof(status));

        char subType[32];
        results.FetchString(1, subType, sizeof(subType));

        strcopy(g_sClientSubscriptionType[client], sizeof(g_sClientSubscriptionType[]), subType);

        if (StrEqual(status, "active", false) && StrEqual(subType, "2", false))
        {
            g_bClientAuthorized[client] = true;
        }
    }

    EvaluateClientAuthorization(client);
}

void EvaluateClientAuthorization(int client)
{
    if (!IsClientConnected(client) || !IsClientInGame(client))
        return;

    if (g_bClientAuthorized[client])
    {
        PrintToServer("[Whitelist] Client %N authorized.", client);
        return;
    }

    char flags[256] = "none";
    AdminId admin = GetUserAdmin(client);

    if (admin != INVALID_ADMIN_ID)
    {
        int userFlags = GetAdminFlags(admin, Access_Effective);
        AdminFlagsToReadableNames(userFlags, flags, sizeof(flags));
    }

    PrintToServer("[Whitelist] Client %N not authorized. Flags: %s.", client, flags);

    if (g_sClientSubscriptionType[client][0] != '\0' && !StrEqual(g_sClientSubscriptionType[client], "2", false))
    {
        PrintToChat(client, "[Whitelist] You are VIP, but not whitelisted. Upgrade your plan at surfing4.fun.");
        KickClient(client, "Upgrade your plan at surfing4.fun to access whitelist");
    }
    else
    {
        PrintToChat(client, "[Whitelist] Access surfing4.fun to purchase whitelist access.");
        KickClient(client, "Visit surfing4.fun to purchase whitelist access");
    }
}

public void OnClientDisconnect(int client)
{
    g_bClientAuthorized[client] = false;
    g_sClientSubscriptionType[client][0] = '\0';
}

void UpdateHostname()
{
    if (g_bWhitelistEnabled)
    {
        ServerCommand("sm_cvar hostname \"[ Surfing4Fun ] [ Whitelist ] Surf\"");
    }
    else
    {
        ServerCommand("sm_cvar hostname \"[ Surfing4Fun ] Surf\"");
    }

    ServerCommand("heartbeat");
}

/**
 * Converts admin flags into a human-readable full name list, like "Generic, Kick, Custom1"
 */
void AdminFlagsToReadableNames(int flags, char[] buffer, int maxlen)
{
    int pos = 0;

    if (flags == 0)
    {
        strcopy(buffer, maxlen, "none");
        return;
    }

    static const char flagNames[][16] =
    {
        "Reservation", // a
        "Generic",     // b
        "Kick",        // c
        "Ban",         // d
        "Unban",       // e
        "Slay",        // f
        "Changemap",   // g
        "Convars",     // h
        "Config",      // i
        "Chat",        // j
        "Vote",        // k
        "Password",    // l
        "RCON",        // m
        "Cheats",      // n
        "Custom1",     // o
        "Custom2",     // p
        "Custom3",     // q
        "Custom4",     // r
        "Custom5",     // s
        "Custom6"      // t
    };

    bool first = true;

    for (int i = 0; i < sizeof(flagNames); i++)
    {
        if (flags & (1 << i))
        {
            if (!first)
            {
                if (pos < maxlen - 2)
                {
                    buffer[pos++] = ',';
                    buffer[pos++] = ' ';
                }
            }
            else
            {
                first = false;
            }

            int len = strlen(flagNames[i]);
            if (pos + len < maxlen)
            {
                strcopy(buffer[pos], maxlen - pos, flagNames[i]);
                pos += len;
            }
            else
            {
                break;
            }
        }
    }

    buffer[pos] = '\0';
}
