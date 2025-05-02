#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <json>

#define MAX_SERVERS 32
#define REFRESH_TIME 60.0
#define CHAT_HINT_TIME 240.0
#define API_URL "https://api.surfing4.fun/server-health"

char g_sServerName[MAX_SERVERS][64];
char g_sMapName[MAX_SERVERS][64];
char g_sPlayers[MAX_SERVERS][16];
char g_sAddress[MAX_SERVERS][32];
int  g_iServerCount;
bool g_bFetching = false;

public Plugin myinfo = {
    name = "Server Hop (API)",
    author = ".sh",
    description = "Fetch server list from HTTP and redirect via menu",
    version = "1.0",
    url = "https://surfing4fun.com"
};

public void OnPluginStart()
{
    PrintToServer("[ServerHop] Plugin started.");
    RegConsoleCmd("sm_servers", Command_Servers);
    RegConsoleCmd("say !servers", Command_Servers);
    RegConsoleCmd("say_team !servers", Command_Servers);
    RegConsoleCmd("say !server", Command_Servers);
    RegConsoleCmd("say_team !server", Command_Servers);

    FetchServerList();
    CreateTimer(REFRESH_TIME, Timer_Refresh, _, TIMER_REPEAT);
    CreateTimer(CHAT_HINT_TIME, Timer_ChatHint, _, TIMER_REPEAT);
}

public Action Timer_Refresh(Handle timer, any data)
{
    PrintToServer("[ServerHop] Refresh timer triggered.");
    FetchServerList();
    return Plugin_Continue;
}

public Action Timer_ChatHint(Handle timer, any data)
{
    PrintToChatAll("\x04[Surfing4Fun]\x01 use \x03!servers\x01 para ver os servidores disponíveis!");
    return Plugin_Continue;
}

void FetchServerList()
{
    if (g_bFetching)
    {
        PrintToServer("[ServerHop] Fetch already in progress.");
        return;
    }

    g_bFetching = true;

    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, API_URL);
    if (request == INVALID_HANDLE)
    {
        PrintToServer("[ServerHop] Failed to create HTTP request.");
        g_bFetching = false;
        return;
    }

    SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 5000);
    SteamWorks_SetHTTPCallbacks(request, OnHTTPResponse);
    SteamWorks_SendHTTPRequest(request);
}

public void OnHTTPResponse(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode statusCode)
{
    if (bFailure || !bRequestSuccessful || statusCode != k_EHTTPStatusCode200OK)
    {
        g_bFetching = false;
        return;
    }

    SteamWorks_GetHTTPResponseBodyCallback(request, OnHTTPResponseBody);
}

public void OnHTTPResponseBody(const char[] body, any data)
{
    int pos = 0;
    JSON_Object root = json_decode(body, _, pos);
    if (root == null)
    {
        g_bFetching = false;
        return;
    }

    JSON_Object servers = root.GetObject("servers");
    if (servers == null || !servers.IsArray)
    {
        delete root;
        g_bFetching = false;
        return;
    }

    g_iServerCount = 0;
    int count = servers.Length;

    for (int i = 0; i < count && i < MAX_SERVERS; i++)
    {
        char indexKey[8];
        IntToString(i, indexKey, sizeof(indexKey));
        JSON_Object entry = servers.GetObject(indexKey);
        if (entry == null) continue;

        if (!entry.HasKey("name") || !entry.HasKey("map") || !entry.HasKey("players") || !entry.HasKey("address"))
            continue;

        char name[64] = "", map[64] = "", players[16] = "", address[32] = "";
        entry.GetString("name",    name,    sizeof(name));
        entry.GetString("map",     map,     sizeof(map));
        entry.GetString("players", players, sizeof(players));
        entry.GetString("address", address, sizeof(address));

        strcopy(g_sServerName[i], sizeof(g_sServerName[]), name);
        strcopy(g_sMapName[i],    sizeof(g_sMapName[]),    map);
        strcopy(g_sPlayers[i],    sizeof(g_sPlayers[]),    players);
        strcopy(g_sAddress[i],    sizeof(g_sAddress[]),    address);

        g_iServerCount++;
    }

    delete root;
    g_bFetching = false;
}

public Action Command_Servers(int client, int args)
{
    if (g_bFetching || g_iServerCount == 0)
    {
        PrintToChat(client, "\x04[ServerHop]\x01 Lista de servidores ainda não está disponível. Tente novamente em alguns segundos.");
        return Plugin_Handled;
    }

    Menu menu = new Menu(MenuHandler, MENU_ACTIONS_DEFAULT);
    menu.SetTitle("Selecione o servidor para entrar");

    char display[256], key[8];
    for (int i = 0; i < g_iServerCount; i++)
    {
        Format(display, sizeof(display),"[%s] %s\nMap: %s",
               g_sPlayers[i],
               g_sServerName[i],
               g_sMapName[i]
        );
        IntToString(i, key, sizeof(key));
        menu.AddItem(key, display);
    }

    menu.Display(client, 0);
    return Plugin_Handled;
}

public int MenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char key[4];
        menu.GetItem(item, key, sizeof(key));
        int idx = StringToInt(key);

        if (idx < 0 || idx >= g_iServerCount)
        {
            PrintToChat(client, "[ServerHop] Servidor inválido.");
            return 0;
        }

        char cmd[80];
        Format(cmd, sizeof(cmd), "redirect %s", g_sAddress[idx]);
        ClientCommand(client, cmd);
        PrintToServer("[ServerHop] Redirecting client %N to %s", client, g_sAddress[idx]);
    }
    else if (action == MenuAction_End)
    {
        delete menu; // Only safe here
    }

    return 0;
}
