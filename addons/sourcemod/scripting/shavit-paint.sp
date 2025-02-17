#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <shavit>

#pragma newdecls required
#pragma semicolon 1

#define PAINT_DISTANCE_SQ 1.0

/* Colour name, file name */
char gS_PaintColors[][][64] =    // Modify this to add/change colours
{
	{"PaintColorRandom",     	"random"         },
	{"PaintColorWhite",      	"paint_white"    },
	{"PaintColorBlack",      	"paint_black"    },
	{"PaintColorBlue",       	"paint_blue"     },
	{"PaintColorLightBlue", 	"paint_lightblue"},
	{"PaintColorBrown",      	"paint_brown"    },
	{"PaintColorCyan",       	"paint_cyan"     },
	{"PaintColorGreen",      	"paint_green"    },
	{"PaintColorDarkGreen", 	"paint_darkgreen"},
	{"PaintColorRed",        	"paint_red"      },
	{"PaintColorOrange",     	"paint_orange"   },
	{"PaintColorYellow",     	"paint_yellow"   },
	{"PaintColorPink",       	"paint_pink"     },
	{"PaintColorLightPink", 	"paint_lightpink"},
	{"PaintColorPurple",     	"paint_purple"   },
};

/* Size name, size suffix */
char gS_PaintSizes[][][64] =    // Modify this to add more sizes
{
	{"PaintSizeSmall",  ""      },
	{"PaintSizeMedium", "_med"  },
	{"PaintSizeLarge",  "_large"},
};


int gI_Sprites[sizeof(gS_PaintColors) - 1][sizeof(gS_PaintSizes)];
int gI_Eraser[sizeof(gS_PaintSizes)];

int gI_PlayerPaintColor[MAXPLAYERS+1];
int gI_PlayerPaintSize[MAXPLAYERS+1];

float gF_LastPaint[MAXPLAYERS+1][3];
bool gB_IsPainting[MAXPLAYERS+1];
bool gB_ErasePaint[MAXPLAYERS+1];
bool gB_PaintToAll[MAXPLAYERS+1];

/* COOKIES */
Cookie gH_PlayerPaintColour;
Cookie gH_PlayerPaintSize;
Cookie gH_PlayerPaintObject;

public Plugin myinfo =
{
	name = "[shavit] Paint",
	author = "SlidyBat, Ciallo-Ani, KikI",
	description = "Allow players to paint on walls.",
	version = "2.2",
	url = "null"
}

public void OnPluginStart()
{
	/* Register Cookies */
	gH_PlayerPaintColour = new Cookie("paint_playerpaintcolour", "paint_playerpaintcolour", CookieAccess_Protected);
	gH_PlayerPaintSize = new Cookie("paint_playerpaintsize", "paint_playerpaintsize", CookieAccess_Protected);
	gH_PlayerPaintObject = new Cookie("paint_playerpaintobject", "paint_playerpaintobject", CookieAccess_Protected);

	/* COMMANDS */
	RegConsoleCmd("+paint", Command_EnablePaint, "Start Painting");
	RegConsoleCmd("-paint", Command_DisablePaint, "Stop Painting");
	RegConsoleCmd("sm_paint", Command_Paint, "Open a paint menu for a client");
	RegConsoleCmd("sm_paintcolour", Command_PaintColour, "Open a paint color menu for a client");
	RegConsoleCmd("sm_paintcolor", Command_PaintColour, "Open a paint color menu for a client");
	RegConsoleCmd("sm_paintsize", Command_PaintSize, "Open a paint size menu for a client");

	LoadTranslations("shavit-paint.phrases");

	/* Late loading */
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientCookiesCached(i);
		}
	}
}

public void OnClientCookiesCached(int client)
{
	char sValue[64];

	gH_PlayerPaintColour.Get(client, sValue, sizeof(sValue));
	gI_PlayerPaintColor[client] = StringToInt(sValue);

	gH_PlayerPaintSize.Get(client, sValue, sizeof(sValue));
	gI_PlayerPaintSize[client] = StringToInt(sValue);

	gH_PlayerPaintObject.Get(client, sValue, sizeof(sValue));
	gB_PaintToAll[client] = sValue[0] == '1';
}

public void OnMapStart()
{
	char buffer[PLATFORM_MAX_PATH];

	AddFileToDownloadsTable("materials/decals/paint/paint_decal.vtf");
	for (int color = 1; color < sizeof(gS_PaintColors); color++)
	{
		for (int size = 0; size < sizeof(gS_PaintSizes); size++)
		{
			Format(buffer, sizeof(buffer), "decals/paint/%s%s.vmt", gS_PaintColors[color][1], gS_PaintSizes[size][1]);
			gI_Sprites[color - 1][size] = PrecachePaint(buffer); // color - 1 because starts from [1], [0] is reserved for random
		}
	}

	for (int size = 0; size < sizeof(gS_PaintSizes); size++)
	{
		Format(buffer, sizeof(buffer), "decals/paint/paint_eraser%s.vmt", gS_PaintSizes[size][1]);
		gI_Eraser[size] = PrecachePaint(buffer); 
	}
}

public Action Command_EnablePaint(int client, int args)
{
	TraceEye(client, gF_LastPaint[client]);
	gB_IsPainting[client] = true;

	return Plugin_Handled;
}

public Action Command_DisablePaint(int client, int args)
{
	gB_IsPainting[client] = false;

	return Plugin_Handled;
}

public Action Command_Paint(int client, int args)
{
	OpenPaintMenu(client);

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (cmdnum % 2 != 0)
	{
		return Plugin_Continue;
	}

	if (IsClientInGame(client) && gB_IsPainting[client])
	{
		static float pos[3];
		TraceEye(client, pos);

		if (GetVectorDistance(pos, gF_LastPaint[client], true) > PAINT_DISTANCE_SQ) 
		{
			if (gB_ErasePaint[client])
			{
				EracePaint(client, pos, gI_PlayerPaintSize[client]);
			}
			else
			{
				AddPaint(client, pos, gI_PlayerPaintColor[client], gI_PlayerPaintSize[client]);
			}			
		}

		gF_LastPaint[client] = pos;
	}

	return Plugin_Continue;
}

void OpenPaintMenu(int client)
{
	Menu menu = new Menu(PaintHelper_MenuHandler);

	menu.SetTitle("%T\n  \n%T", "PaintMenuTitle", client, "PaintTips", client);

	char sMenuItem[64];
	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintColor", client, gS_PaintColors[gI_PlayerPaintColor[client]][0], client);
	menu.AddItem("color", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintSize", client, gS_PaintSizes[gI_PlayerPaintSize[client]][0], client);
	menu.AddItem("size", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T\n ", "PaintObject", client, gB_PaintToAll[client] ? "ObjectAll":"ObjectSingle", client);
	menu.AddItem("object", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintEraser", client, gB_ErasePaint[client] ? "EraserOn":"EraserOff", client);
	menu.AddItem("erase", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "PaintClear", client);
	menu.AddItem("clear", sMenuItem);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int PaintHelper_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "color"))
		{
			OpenPaintColorMenu(param1);
		}
		else if(StrEqual(sInfo, "size"))
		{
			OpenPaintSizeMenu(param1);
		}
		else if(StrEqual(sInfo, "erase"))
		{
			gB_ErasePaint[param1] = !gB_ErasePaint[param1];
			OpenPaintMenu(param1);
		}
		else if(StrEqual(sInfo, "clear"))
		{
			ClientCommand(param1,"r_cleardecals");
			Shavit_PrintToChat(param1, "%T", "PaintCleared", param1);
			OpenPaintMenu(param1);
		}
		else if(StrEqual(sInfo, "object"))
		{
			gB_PaintToAll[param1] = !gB_PaintToAll[param1];

			char sValue[8];
			IntToString(view_as<int>(gB_PaintToAll[param1]), sValue, sizeof(sValue));
			gH_PlayerPaintObject.Set(param1, sValue);
			OpenPaintMenu(param1);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_PaintColour(int client, int args)
{
	OpenPaintColorMenu(client);

	return Plugin_Continue;
}

void OpenPaintColorMenu(int client, int item = 0)
{
	Menu menu = new Menu(PaintColour_MenuHandler);

	menu.SetTitle("%T\n ", "PaintColorMenuTitle", client);
	
	char sMenuItem[64];
	for (int i = 0; i < sizeof(gS_PaintColors); i++)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", gS_PaintColors[i][0], client);

		menu.AddItem("", sMenuItem, gI_PlayerPaintColor[client] == i ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int PaintColour_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sValue[64];
		gI_PlayerPaintColor[param1] = param2;
		IntToString(param2, sValue, sizeof(sValue));
		gH_PlayerPaintColour.Set(param1, sValue);

		OpenPaintColorMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Cancel)
	{
		OpenPaintMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_PaintSize(int client, int args)
{
	OpenPaintSizeMenu(client);

	return Plugin_Continue;
}

void OpenPaintSizeMenu(int client, int item = 0)
{
	Menu menu = new Menu(PaintSize_MenuHandler);

	menu.SetTitle("%T\n ", "PaintSizeMenuTitle", client);

	char sMenuItem[64];
	for (int i = 0; i < sizeof(gS_PaintSizes); i++)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", gS_PaintSizes[i][0], client);
		menu.AddItem("", sMenuItem, gI_PlayerPaintSize[client] == i ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int PaintSize_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sValue[64];
		gI_PlayerPaintSize[param1] = param2;
		IntToString(param2, sValue, sizeof(sValue));
		gH_PlayerPaintSize.Set(param1, sValue);

		OpenPaintSizeMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Cancel)
	{
		OpenPaintMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void AddPaint(int client, float pos[3], int paint = 0, int size = 0)
{
	if(paint == 0)
	{
		paint = GetRandomInt(1, sizeof(gS_PaintColors) - 1);
	}

	TE_SetupWorldDecal(pos, gI_Sprites[paint - 1][size]);

	if (gB_PaintToAll[client])
	{
		TE_SendToAll();
	}
	else
	{
		TE_SendToClient(client);
	}
}

void EracePaint(int client, float pos[3], int size = 0)
{
	TE_SetupWorldDecal(pos, gI_Eraser[size]);
	TE_SendToClient(client);
}

int PrecachePaint(char[] filename)
{
	char tmpPath[PLATFORM_MAX_PATH];
	Format(tmpPath, sizeof(tmpPath), "materials/%s", filename);
	AddFileToDownloadsTable(tmpPath);

	return PrecacheDecal(filename, true);
}

stock void TE_SetupWorldDecal(const float vecOrigin[3], int index)
{
	TE_Start("World Decal");
	TE_WriteVector("m_vecOrigin", vecOrigin);
	TE_WriteNum("m_nIndex", index);
}

stock void TraceEye(int client, float pos[3])
{
	float vAngles[3], vOrigin[3];
	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	TR_TraceRayFilter(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if (TR_DidHit())
	{
		TR_GetEndPosition(pos);
	}
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	return (entity > MaxClients || !entity);
}