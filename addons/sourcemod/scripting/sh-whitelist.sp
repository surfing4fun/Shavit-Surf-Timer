/**
 * Plugin: Simple Group Whitelist
 * Author: Sh ft. ChatGPT
 * Description: Only allows clients who are members of a specified Steam group.
 *              Provides an admin command (sm_wldump) to dump all whitelist entries.
 * Version: 1.2
 */
#pragma dynamic 69696
#include <sourcemod>
#include <sdktools>
#include <SteamWorks>

ConVar g_GroupID;          // The Steam group ID as a string (64-bit)
ConVar g_RefreshInterval;  // How often (in seconds) to refresh the whitelist

// Our whitelist is stored as a StringMap (trie) with keys as account IDs (as strings)
StringMap g_Whitelist = null;

public Plugin myinfo =
{
    name = "Simple Group Whitelist",
    author = "Sh ft. ChatGPT",
    description = "Only allows clients who are members of a specified Steam group. Use sm_wldump to dump whitelist.",
    version = "1.2"
};

public void OnPluginStart()
{
    // Create ConVars.
    g_GroupID = CreateConVar("sgw_groupid", "103582791475007519", "Steam group ID for whitelist", FCVAR_NONE);
    g_RefreshInterval = CreateConVar("sgw_refresh", "300", "Whitelist refresh interval (seconds)", FCVAR_NONE);

    // Create the whitelist StringMap.
    g_Whitelist = new StringMap();

    // Register admin command to dump the whitelist.
    RegAdminCmd("sm_wldump", Command_DumpWhitelist, ADMFLAG_GENERIC, "Dump all whitelist entries.");

    // Immediately attempt to load the whitelist.
    ReloadWhitelist();

    // Set a repeating timer to refresh the whitelist periodically.
    CreateTimer(g_RefreshInterval.FloatValue, Timer_ReloadWhitelist, _, TIMER_REPEAT);
}

/**
 * Timer callback to refresh the whitelist.
 */
public Action Timer_ReloadWhitelist(Handle timer, any data)
{
    ReloadWhitelist();
    return Plugin_Continue;
}

/**
 * ReloadWhitelist() sends an HTTP request to Steam to fetch the group's XML,
 * then uses a callback to retrieve the response body and parse out all <steamID64> values.
 */
public void ReloadWhitelist()
{
    char groupid[32];
    g_GroupID.GetString(groupid, sizeof(groupid));

    char url[256];
    Format(url, sizeof(url), "https://steamcommunity.com/gid/%s/memberslistxml/?xml=1", groupid);
    PrintToServer("[Whitelist] URL: %s", url);

    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
    if (request == INVALID_HANDLE)
    {
        PrintToServer("[Whitelist] Failed to create HTTP request for URL: %s", url);
        return;
    }

    // Set a 5-second timeout.
    SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 5000);

    // Set our callback for when the HTTP request completes.
    SteamWorks_SetHTTPCallbacks(request, HTTPCallback);
    SteamWorks_SendHTTPRequest(request);
}

/**
 * HTTPCallback() is invoked when the HTTP request for the group XML completes.
 * We use the callback method to retrieve the response body.
 */
public void HTTPCallback(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
    if(bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
    {
        PrintToServer("[Whitelist] HTTP request failed. Status: %d", eStatusCode);
        return;
    }
    
    bool callbackSet = SteamWorks_GetHTTPResponseBodyCallback(request, WhitelistBodyCallback, request);
    PrintToServer("[Whitelist] SteamWorks_GetHTTPResponseBodyCallback returned: %d", callbackSet);
}

/**
 * WhitelistBodyCallback() is invoked when the HTTP response body is ready.
 */
public void WhitelistBodyCallback(const char[] sData, any data)
{
    // int reqHandle = data;
    // PrintToServer("[Whitelist] WhitelistBodyCallback invoked for request handle: %d", reqHandle);
    // PrintToServer("[Whitelist] Received XML:\n%s", sData);
    ParseWhitelistXML(sData);
}

/**
 * ParseWhitelistXML() scans the XML response and extracts all <steamID64> values.
 * Each steamID64 is converted to an account ID (as an int) and stored in g_Whitelist.
 * Debug messages are printed for each entry.
 */
public void ParseWhitelistXML(const char[] data)
{
    // Clear previous whitelist entries.
    g_Whitelist.Clear();

    // PrintToServer("[Whitelist Debug] Starting XML parsing...");

    int pos = 0;
    int start, end;
    char steamID64[32];

    while ((start = FindStringOffset(data, "<steamID64>", pos)) != -1)
    {
        start += strlen("<steamID64>");
        end = FindStringOffset(data, "</steamID64>", start);
        if (end == -1)
            break;

        int len = end - start;
        if (len >= sizeof(steamID64))
            len = sizeof(steamID64) - 1;

        for (int i = 0; i < len; i++)
        {
            steamID64[i] = data[start + i];
        }
        steamID64[len] = '\0';

        // PrintToServer("[Whitelist Debug] Found steamID64: %s", steamID64);

        int accountID = SteamID64ToAccountID(steamID64);
        char accountStr[16];
        IntToString(accountID, accountStr, sizeof(accountStr));

        // PrintToServer("[Whitelist Debug] Converted %s to accountID: %d", steamID64, accountID);

        // Store the account ID in the whitelist.
        g_Whitelist.SetValue(accountStr, "1");

        pos = end + strlen("</steamID64>");
    }
    // PrintToServer("[Whitelist Debug] Finished XML parsing. Reloaded whitelist.");
}

/**
 * Converts a SteamID64 (as string) to an account ID.
 * (Conversion: accountID = (steamID64 - 76561197960265728) & 0xFFFFFFFF)
 */
stock int SteamID64ToAccountID(const char[] steamid64)
{
    int num[2];
    StringToInt64(steamid64, num);
    return num[0];
}

/**
 * OnClientAuthorized() is called when a client has been authenticated.
 * The client's Steam AuthID is converted to an account ID and compared against the whitelist.
 * Bots are skipped.
 */
public void OnClientAuthorized(int client, const char[] authstring)
{
    if (!IsClientConnected(client))
        return;

    // Skip bots.
    if (IsFakeClient(client))
    {
        PrintToServer("[Whitelist Debug] Client %N is a bot. Skipping whitelist check.", client);
        return;
    }

    char authID[32];
    GetClientAuthId(client, AuthId_Steam2, authID, sizeof(authID), true);
    PrintToServer("[Whitelist Debug] Client %N raw authID: %s", client, authID);

    int accountID = SteamIDToAccountID(authID);
    char accountStr[16];
    IntToString(accountID, accountStr, sizeof(accountStr));
    // PrintToServer("[Whitelist Debug] Converted client %N authID to accountID: %s", client, accountStr);

    bool whitelisted = IsAccountWhitelisted(accountStr);
    // PrintToServer("[Whitelist Debug] Lookup for account %s: whitelisted=%d", accountStr, whitelisted);

    if (!whitelisted)
    {
        PrintToServer("[Whitelist] Client %N (account %s) is NOT whitelisted. Kicking...", client, accountStr);
        KickClient(client, "You are not whitelisted on this server.");
    }
    else
    {
        PrintToServer("[Whitelist] Client %N is whitelisted.", client);
    }
}

/**
 * Converts a Steam ID (as a string) to an account ID.
 * Supports STEAM_X:Y:Z, [U:1:123], and 64-bit IDs.
 */
stock int SteamIDToAccountID(const char[] sInput)
{
    char sSteamID[32];
    strcopy(sSteamID, sizeof(sSteamID), sInput);
    ReplaceString(sSteamID, sizeof(sSteamID), "\"", "");
    TrimString(sSteamID);

    if (StrContains(sSteamID, "STEAM_") != -1)
    {
        ReplaceString(sSteamID, sizeof(sSteamID), "STEAM_", "");
        char parts[3][11];
        ExplodeString(sSteamID, ":", parts, 3, 11);
        return StringToInt(parts[2]) * 2 + StringToInt(parts[1]);
    }
    else if (StrContains(sSteamID, "U:1:") != -1)
    {
        ReplaceString(sSteamID, sizeof(sSteamID), "[", "");
        ReplaceString(sSteamID, sizeof(sSteamID), "U:1:", "");
        ReplaceString(sSteamID, sizeof(sSteamID), "]", "");
        return StringToInt(sSteamID);
    }
    else if (StrContains(sSteamID, "765") == 0)
    {
        return SteamID64ToAccountID(sSteamID);
    }
    return 0;
}

/**
 * IsAccountWhitelisted() creates a snapshot of g_Whitelist and iterates over all keys
 * to check if the given account key exists.
 */
stock bool IsAccountWhitelisted(const char[] key)
{
    Handle snapshot = CreateTrieSnapshot(g_Whitelist);
    if (snapshot == INVALID_HANDLE)
    {
        PrintToServer("[Whitelist Debug] Failed to create trie snapshot in IsAccountWhitelisted.");
        return false;
    }

    int keyCount = TrieSnapshotLength(snapshot);
    bool found = false;
    for (int i = 0; i < keyCount; i++)
    {
        int keySize = TrieSnapshotKeyBufferSize(snapshot, i);
        if (keySize <= 0)
            continue;
        char temp[64];
        if (GetTrieSnapshotKey(snapshot, i, temp, sizeof(temp)))
        {
            if (StrEqual(temp, key))
            {
                found = true;
                break;
            }
        }
    }
    CloseHandle(snapshot);
    return found;
}

/**
 * FindStringOffset() is a helper function that searches for a substring (needle)
 * in a larger string (haystack) starting from a given offset.
 * Returns the index of the first occurrence, or -1 if not found.
 */
stock int FindStringOffset(const char[] haystack, const char[] needle, int start = 0)
{
    int hayLen = strlen(haystack);
    int needleLen = strlen(needle);
    if (needleLen <= 0 || hayLen < needleLen || start < 0 || start >= hayLen)
    {
        return -1;
    }
    for (int i = start; i <= hayLen - needleLen; i++)
    {
        bool match = true;
        for (int j = 0; j < needleLen; j++)
        {
            if (haystack[i + j] != needle[j])
            {
                match = false;
                break;
            }
        }
        if (match)
        {
            return i;
        }
    }
    return -1;
}

/**
 * Command_DumpWhitelist() is an admin command to dump all keys stored in g_Whitelist.
 * It creates a trie snapshot of g_Whitelist and iterates over the keys.
 */
public Action Command_DumpWhitelist(int client, int args)
{
    Handle snapshot = CreateTrieSnapshot(g_Whitelist);
    if (snapshot == INVALID_HANDLE)
    {
        PrintToServer("[Whitelist Dump] Failed to create trie snapshot.");
        return Plugin_Handled;
    }

    int keyCount = TrieSnapshotLength(snapshot);
    PrintToServer("[Whitelist Dump] Total whitelist entries: %d", keyCount);

    for (int i = 0; i < keyCount; i++)
    {
        int keySize = TrieSnapshotKeyBufferSize(snapshot, i);
        if (keySize <= 0)
            continue;
        char key[64]; // fixed buffer large enough for our keys
        if (GetTrieSnapshotKey(snapshot, i, key, sizeof(key)))
        {
            PrintToServer("[Whitelist Dump] Entry %d: %s", i, key);
        }
    }

    CloseHandle(snapshot);
    return Plugin_Handled;
}
