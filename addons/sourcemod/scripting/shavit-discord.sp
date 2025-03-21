#include <sourcemod>
#include <shavit>
#include <SteamWorks>
#include <sdktools>
#include <steamworks-profileurl>
#include <shavit/core>
#include <shavit/hud>
#include <shavit/steamid-stocks>

// Retry count plugin :D
int gI_RestartCounter[MAXPLAYERS+1];
public void OnClientPutInServer(int client)
{
	gI_RestartCounter[client] = -2;
}

public void Shavit_OnRestart(int client, int track)
{
	gI_RestartCounter[client] += 1;
}

public Action Shavit_OnTopLeftHUD(int client, int target, char[] topleft, int topleftlength, int track, int style)
{
	if (1 <= target < MaxClients)
	{
		FormatEx(topleft, topleftlength, "RESTART COUNTER = %d", gI_RestartCounter[target]);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}
// Retry count plugin :D

#pragma newdecls required
#pragma semicolon 1

char g_sMapName[PLATFORM_MAX_PATH];
char g_sMapTier[PLATFORM_MAX_PATH];

int g_iMainColor;
int g_iBonusColor;
int g_iStageCount;

Handle g_hWRTrie;

int gI_Driver = Driver_unknown;
Database gH_SQL = null;

ConVar g_cvHostname;
ConVar g_cvHostPort;
ConVar g_cvIpAddress;
ConVar g_cvWebhookRecords;
ConVar g_cvWebhookMapChange;
ConVar g_cvBotProfilePicture;
ConVar g_cvMinimumrecords;
ConVar g_cvBotUsername;
ConVar g_cvFooterUrl;
ConVar g_cvMainEmbedColor;
ConVar g_cvBonusEmbedColor;
ConVar g_cvSendBonusRecords;
ConVar g_cvSendOffstyleRecords;
ConVar g_cvSendStageRecords;

public Plugin myinfo =
{
    name = "[shavit] Discord WR Bot (Steamworks)",
    author = "SlidyBat, improved by Sarrus / nimmy",
    description = "Makes discord bot post message when server WR is beaten",
    version = "2.4",
    url = "https://github.com/Nimmy2222/shavit-discord"
};

public void OnPluginStart()
{
    g_cvMinimumrecords = CreateConVar("shavit-discord-min-record", "0", "Minimum number of records before they are sent to the discord channel.", _, true, 0.0);
    g_cvWebhookRecords = CreateConVar("shavit-discord-webhook-records", "", "The webhook to the discord channel where you want record messages to be sent.", FCVAR_PROTECTED);
    g_cvWebhookMapChange = CreateConVar("shavit-discord-webhook-server-status", "", "The webhook to the discord channel where you want record messages to be sent.", FCVAR_PROTECTED);
    g_cvBotProfilePicture = CreateConVar("shavit-discord-profilepic", "https://i.imgur.com/fKL31aD.jpg", "link to pfp for the bot");
    g_cvFooterUrl = CreateConVar("shavit-discord-footer-url", "https://images-ext-1.discordapp.net/external/tfTL-r42Kv1qP4FFY6sQYDT1BBA2fXzDjVmcknAOwNI/https/images-ext-2.discordapp.net/external/3K6ho0iMG_dIVSlaf0hFluQFRGqC2jkO9vWFUlWYOnM/https/images-ext-2.discordapp.net/external/aO9crvExsYt5_mvL72MFLp92zqYJfTnteRqczxg7wWI/https/discordsl.com/assets/img/img.png", "The url of the footer icon, leave blank to disable.");
    g_cvBotUsername = CreateConVar("sm_bhop_discord_username", "World Records", "Username of the bot");
    g_cvMainEmbedColor = CreateConVar("shavit-discord-main-color", "255, 0, 0", "Color of embed for when main wr is beaten");
    g_cvBonusEmbedColor = CreateConVar("shavit-discord-bonus-color", "0, 255, 0", "Color of embed for when bonus wr is beaten");
    g_cvSendBonusRecords = CreateConVar("shavit-discord-send-bonus", "1", "Whether to send bonus records or not 1 Enabled 0 Disabled");
    g_cvSendOffstyleRecords = CreateConVar("shavit-discord-send-offstyle", "1", "Whether to send offstyle records or not 1 Enabled 0 Disabled");
    g_cvSendStageRecords = CreateConVar("shavit-discord-send-stage", "0", "Wheter to send a stage record or not 1 Enabled 0 Disabled");
    g_cvHostname = FindConVar("hostname");
    g_cvIpAddress = FindConVar("ip");
    g_cvHostPort = FindConVar("hostport");

    HookConVarChange(g_cvMainEmbedColor, CvarChanged);
    HookConVarChange(g_cvBonusEmbedColor, CvarChanged);

    UpdateColorCvars();

    g_hWRTrie = CreateTrie();

    RegAdminCmd("sm_discordtest", CommandDiscordTest, ADMFLAG_ROOT);
    AutoExecConfig(true, "plugin.shavit-discord-steamworks");
}

public void UpdateColorCvars()
{
    char sMainColor[32];
    char sBonusColor[32];
    g_cvMainEmbedColor.GetString(sMainColor, sizeof(sMainColor));
    g_cvBonusEmbedColor.GetString(sBonusColor, sizeof(sBonusColor));
    g_iMainColor = RGBStrToShiftedInt(sMainColor);
    g_iBonusColor = RGBStrToShiftedInt(sBonusColor);
}

int RGBStrToShiftedInt(char fullStr[32])
{
    char rgbStrs[3][5];
    int strs = ExplodeString(fullStr, ",", rgbStrs, sizeof(rgbStrs), sizeof(rgbStrs[]));
    if (strs < 3)
    {
        return 255 << (2 * 8);
    }
    int adjustedInt;
    for (int i = 0; i < 3; i++)
    {
        int color = StringToInt(rgbStrs[i]);
        adjustedInt = (adjustedInt & ~(255 << ((2 - i) * 8))) | ((color & 255) << ((2 - i) * 8));
    }
    return adjustedInt;
}

public void CvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateColorCvars();
}

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    StringMap tiersMap = null;
    int tier = 0;
    g_iStageCount = Shavit_GetStageCount(Track_Main);
	  tiersMap = Shavit_GetMapTiers();
    tiersMap.GetValue(g_sMapName, tier);
    Format(g_sMapTier, sizeof(g_sMapTier), "%s", tier);

    gH_SQL = Shavit_GetDatabase(gI_Driver);
    char sQuery[512];
    FormatEx(sQuery, sizeof(sQuery), "SELECT wrs.style, wrs.track, wrs.auth, users.name, users.steamID FROM wrs LEFT JOIN users ON wrs.auth = users.auth WHERE wrs.map = '%s';", g_sMapName);
    QueryLog(gH_SQL, SQL_GetActualWRList_Callback, sQuery, 0, DBPrio_High);

    // [TODO] Refactor
    char webhook[256];
    g_cvWebhookMapChange.GetString(webhook, sizeof(webhook));
    if (webhook[0] == '\0')
    {
        LogError("Discord webhook is not set.");
        return;
    }

    char botUserName[128];
    g_cvBotUsername.GetString(botUserName, sizeof(botUserName));

    char botAvatar[1024];
    g_cvBotProfilePicture.GetString(botAvatar, sizeof(botAvatar));

    char recordTxt[64];
    Format(recordTxt, sizeof(recordTxt), "%s", "Teste");
    // Construct the final JSON string in one Format() call.
    char jsonStr[4096];
    Format(jsonStr, sizeof(jsonStr),
        "{\"username\":\"%s\",\"avatar_url\":\"%s\",\"embeds\":[{\"title\":\"%s\"}]}",
        botUserName,
        botAvatar,
        recordTxt);

    SendMessageRaw(jsonStr, webhook);
}

public void SQL_GetActualWRList_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if (results == null)
    {
        LogError("SQL query failed: %s", error);
        return;
    }

    while (results.FetchRow())
    {
        int style = results.FetchInt(0);
        int track = results.FetchInt(1);

        int steamID = results.FetchInt(2);
        // Fetch the extra 'name' field from users (assumed to be the 5th column)
        char sName[128];
        results.FetchString(3, sName, sizeof(sName));
        
        // Fetch steam id 64
        // char sSteamID[128];
        // results.FetchString(4, sSteamID, sizeof(sSteamID));


        char steam64[40];
		    AccountIDToSteamID64(steamID, steam64, sizeof(steam64));

        char key[64];
        Format(key, sizeof(key), "%d_%d", style, track);

        // Combine auth and sName into one string (using a '|' as a delimiter)
        char combinedValue[128];
        Format(combinedValue, sizeof(combinedValue), "%s|%s", steam64, sName);

        PrintToServer("%i|%s", steamID, steam64);
        SetTrieString(g_hWRTrie, key, combinedValue);
    }
}

void ProcessTrieEntry(const char[] key, char[] authOut, int authOutLen, char[] nameOut, int nameOutLen)
{
    char combinedValue[128];
    if (!GetTrieString(g_hWRTrie, key, combinedValue, 64))
    {
        PrintToServer("No trie entry found for key: %s", key);
        return;
    }
    
    int pos = StrContains(combinedValue, "|", false);
    if (pos == -1)
    {
        PrintToServer("Error: The trie value is not in the expected format.");
        return;
    }
    
    char authStr[40];
    int iterate = 0;
    for (iterate = 0; iterate < pos && iterate < sizeof(authStr)-1; iterate++)
    {
        authStr[iterate] = combinedValue[iterate];
    }
    authStr[iterate] = '\0';  // Null-terminate the string.

    char nameStr[64];
    int nameIndex = 0;
    for (int i = pos + 1; combinedValue[i] != '\0' && nameIndex < sizeof(nameStr) - 1; i++, nameIndex++)
    {
        nameStr[nameIndex] = combinedValue[i];
    }
    nameStr[nameIndex] = '\0';
    
    strcopy(nameOut, nameOutLen, nameStr);
    strcopy(authOut, authOutLen, authStr);
}

public Action CommandDiscordTest(int client, int args)
{
    int track = GetCmdArgInt(1);
    int style = GetCmdArgInt(2);
    Shavit_OnWorldRecord(client, style, 12.3, 35, 23, 93.25, track, 2, 17.01);
    PrintToChat(client, "[shavit-discord] Discord Test Message has been sent.");
    return Plugin_Handled;
}

// Listen
public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, int stage, float oldwr)
{
    if (g_cvMinimumrecords.IntValue > 0 && Shavit_GetRecordAmount(style, track) < g_cvMinimumrecords.IntValue)
    {
        return;
    }
    if (!(g_cvSendOffstyleRecords.IntValue) && style != 0)
    {
        return;
    }
    if (!(g_cvSendBonusRecords.IntValue) && track != Track_Main)
    {
        return;
    }
    if (!(g_cvSendStageRecords.IntValue) && stage != g_iStageCount) {
        return;
    }

    FormatEmbedMessage(client, style, time, jumps, strafes, sync, track, oldwr);
}

// Manually construct JSON string to avoid heap allocations from JSON objects.
void FormatEmbedMessage(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr)
{
    char styleMsg[512];
    Shavit_GetStyleStrings(style, sStyleName, styleMsg, sizeof(styleMsg));

    char recordTxt[1024];
    if (track == Track_Main)
    {
        Format(recordTxt, sizeof(recordTxt), "Tier %i · Track: Main · Style: %s · Points: [???]", g_sMapTier, styleMsg);
    }
    else
    {
        Format(recordTxt, sizeof(recordTxt), "Tier %i · Track: Bonus %i · Style: %s · Points: [???]", g_sMapTier, track, styleMsg);
    }

    char authId[64];
    GetClientAuthId(client, AuthId_SteamID64, authId, sizeof(authId));

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    SanitizeName(name);

    char playerUrl[512];
    Format(playerUrl, sizeof(playerUrl), "http://www.steamcommunity.com/profiles/%s", authId);

    char playerProfilePicture[1024];
    if (!Sw_GetProfileUrl(client, playerProfilePicture, sizeof(playerProfilePicture)))
    {
        PrintToConsole(client, "Shavit-Discord: Failed to find profile picture URL");
        g_cvBotProfilePicture.GetString(playerProfilePicture, sizeof(playerProfilePicture));
    }

    char styleTrack[64];
    Format(styleTrack, sizeof(styleTrack), "%d_%d", style, track);

    // Me mama Proxychains
    char oldWRPlayerAuth[64];
    char oldWRPlayerName[64];
    ProcessTrieEntry(styleTrack, oldWRPlayerAuth, sizeof(oldWRPlayerAuth), oldWRPlayerName, sizeof(oldWRPlayerName));
    SanitizeName(oldWRPlayerName);

    char oldWRPlayerUrl[512];
    Format(oldWRPlayerUrl, sizeof(oldWRPlayerUrl), "http://www.steamcommunity.com/profiles/%s", oldWRPlayerAuth);

    char newTimeStr[32];
    FormatSeconds(time, newTimeStr, sizeof(newTimeStr));
    Format(newTimeStr, sizeof(newTimeStr), "%ss", newTimeStr);

    char oldWrTimeStr[32];
    FormatSeconds(oldwr, oldWrTimeStr, sizeof(oldWrTimeStr));
    Format(oldWrTimeStr, sizeof(oldWrTimeStr), "%ss", oldWrTimeStr);

    float diff = time - oldwr;
    char diffWrTimeStr[32];
    FormatSeconds(diff, diffWrTimeStr, sizeof(diffWrTimeStr));
    Format(diffWrTimeStr, sizeof(diffWrTimeStr), "%ss", diffWrTimeStr);

    char statsFieldValue[128];
    Format(statsFieldValue, sizeof(statsFieldValue), "Strafes: %i · Sync: %.2f%% · Jumps: %i · Attempts: %i", strafes, sync, jumps, gI_RestartCounter[client]);

    char hostname[512];
    g_cvHostname.GetString(hostname, sizeof(hostname));

    char ipAddress[512];
    g_cvIpAddress.GetString(ipAddress, sizeof(ipAddress));

    char hostPort[512];
    g_cvHostPort.GetString(hostPort, sizeof(hostPort));

    char footerUrl[1024];
    g_cvFooterUrl.GetString(footerUrl, sizeof(footerUrl));

    char mapImageUrl[1024];
    if (track == Track_Main)
    {
        Format(mapImageUrl, sizeof(mapImageUrl), "https://raw.githubusercontent.com/GimoDDak/SurfMapPics/refs/heads/Maps-and-bonuses/csgo/%s.jpg", g_sMapName);
    }
    else
    {
        Format(mapImageUrl, sizeof(mapImageUrl), "https://raw.githubusercontent.com/GimoDDak/SurfMapPics/refs/heads/Maps-and-bonuses/csgo/%s_b%i.jpg", g_sMapName, track);
    }

    char color[32];
    Format(color, sizeof(color), "%i", (track == Track_Main && style == 0) ? g_iMainColor : g_iBonusColor);

    char botUserName[128];
    g_cvBotUsername.GetString(botUserName, sizeof(botUserName));

    char botAvatar[1024];
    g_cvBotProfilePicture.GetString(botAvatar, sizeof(botAvatar));

    // Construct the final JSON string in one Format() call.
    char jsonStr[4096];
    Format(jsonStr, sizeof(jsonStr), "{\"username\":\"%s\",\"avatar_url\":\"%s\",\"embeds\":[{\"description\":\"%s\",\"color\":\"%s\",\"author\":{\"name\":\"New server record on %s!\",\"url\":\"%s\",\"icon_url\":\"%s\"},\"fields\":[{\"name\":\"Player\",\"value\":\"[%s](%s)\",\"inline\":true},{\"name\":\"Time\",\"value\":\"%s\\n*(%s)*\",\"inline\":true},{\"name\":\"Previous time\",\"value\":\"%s\\n[%s](%s)\",\"inline\":true},{\"name\":\"Run stats\",\"value\":\"%s\"}],\"image\":{\"url\":\"%s\"},\"footer\":{\"text\":\"%s  ·  steam://connect/%s:%s\",\"icon_url\":\"%s\"}}]}", 
      botUserName, 
      botAvatar, 
      recordTxt, 
      color, 
      g_sMapName,
      playerUrl, 
      playerProfilePicture, 
      name, 
      playerUrl, 
      newTimeStr, 
      diffWrTimeStr,
      oldWrTimeStr,
      oldWRPlayerName,
      oldWRPlayerUrl,
      statsFieldValue,
      mapImageUrl,
      hostname,
      ipAddress,
      hostPort,
      footerUrl
    );

    // [TODO] Refactor
    char webhook[256];
    g_cvWebhookRecords.GetString(webhook, sizeof(webhook));
    if (webhook[0] == '\0')
    {
        LogError("Discord webhook is not set.");
        return;
    }
    
    SendMessageRaw(jsonStr, webhook);
}

void SendMessageRaw(const char[] jsonStr, const char[] webhook)
{
    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, webhook);
    SteamWorks_SetHTTPRequestRawPostBody(request, "application/json", jsonStr, strlen(jsonStr));
    SteamWorks_SetHTTPCallbacks(request, OnMessageSent);
    SteamWorks_SendHTTPRequest(request);
}

public void OnMessageSent(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, DataPack pack)
{
    if (failure || !requestSuccessful || statusCode != k_EHTTPStatusCode204NoContent)
    {
        LogError("Failed to send message to Discord. Response status: %d.", statusCode);
    }
    delete request;
}

void SanitizeName(char[] name)
{
    ReplaceString(name, MAX_NAME_LENGTH, "(", "", false);
    ReplaceString(name, MAX_NAME_LENGTH, ")", "", false);
    ReplaceString(name, MAX_NAME_LENGTH, "]", "", false);
    ReplaceString(name, MAX_NAME_LENGTH, "[", "", false);
}