#include <sourcemod>
#include <convar_class>
#include <shavit/core>
#include <shavit/zones>
#include <shavit/wr>
#include <shavit/wrsh>
#include <ripext>

Convar gCV_MaxRequest;
Convar gCV_RetryInterval;
Convar gCV_RankingCoolDown;
// Convar gCV_RefreshRecordInterval;

wrinfo_t gA_MapWorldRecord[TRACKS_SIZE];
wrinfo_t gA_StageWorldRecord[MAX_STAGES];

chatstrings_t gS_ChatStrings;

char gS_Map[PLATFORM_MAX_PATH];
char gS_PreviousMap[PLATFORM_MAX_PATH];

int gI_RequestTimes;
bool gB_Fetching = false;
bool gB_MapWRCached = false;
bool gB_StageWRCached = false;
bool gB_CacheFail = false;

float gF_ReadyTime[MAXPLAYERS + 1];
bool gB_CoolDown[MAXPLAYERS + 1];
Handle gH_CoolDown[MAXPLAYERS + 1];

bool gB_Late;

public Plugin myinfo =
{
	name = "[shavit-surf] WR-SH",
	author = "KikI",
	description = "Fetching top records of current maps from Surf Heaven.",
	version = "0.0.1",
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	//natives
	CreateNative("Shavit_GetSHMapRecordTime", Native_GetSHMapRecordTime);
	CreateNative("Shavit_GetSHMapRecordName", Native_GetSHMapRecordName);
	CreateNative("Shavit_GetSHStageRecordTime", Native_GetSHStageRecordTime);
	CreateNative("Shavit_GetSHStageRecordName", Native_GetSHStageRecordName);

	RegPluginLibrary("shavit-wrsh");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");

	RegConsoleCmd("sm_shmaprank", Command_SHMapRank, "Print client's rank of map time in SurfHeaven");
	RegConsoleCmd("sm_shrank", Command_SHMapRank, "Print client's rank of map time in SurfHeaven");

	RegConsoleCmd("sm_shstagerank", Command_SHStageRank, "Print client's rank of stage time in SurfHeaven");
	RegConsoleCmd("sm_shsrank", Command_SHStageRank, "Print client's rank of stage time in SurfHeaven");

	RegAdminCmd("sm_reloadshrecord", Command_ReloadSHRecord, ADMFLAG_CHANGEMAP, "Reload SH record.")

	gCV_MaxRequest = new Convar("shavit_wrsh_maxrequest", "10", "Maximum number of requests with no response sent.", 0, true, 1.0, false, 0.0);
	gCV_RetryInterval = new Convar("shavit_wrsh_retryinterval", "10.0", "The interval between sending requests if records are not cached.", 0, true, 10.0, false, 0.0);
	gCV_RankingCoolDown = new Convar("shavit_wrsh_rankingcooldown", "30.0", "The interval (in seconds) allow client use rank command again.", 0, true, 30.0, false, 0.0);
	// gCV_RefreshRecordInterval = new Convar("shavit_wrsh_refreshinterval", "30", "How often (in minutes) should refresh records.", 0, true, -1, false, 0);
	Convar.AutoExecConfig();

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
		OnMapStart();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public Action Command_ReloadSHRecord(int client, int args)
{
	if(gB_Fetching)
	{
		Shavit_PrintToChat(client, "Plugin is fetching data currently, please try again later.");
		return Plugin_Handled;
    }

	Shavit_LogMessage("%L - Reload sh records for %s", client, gS_Map);
	ResetWRCache();
	CacheWorldRecord(gS_Map);

	return Plugin_Handled;
}

public Action Command_SHMapRank(int client, int args)
{
	if(gB_CoolDown[client])
	{
		Shavit_PrintToChat(client, "You just ranking few seconds ago, please wait %s%.1f %sseconds before using this command.",
		gS_ChatStrings.sVariable2, gF_ReadyTime[client] - GetEngineTime(), gS_ChatStrings.sText);
		return Plugin_Handled;
	}
	
	if(gB_Fetching)
	{
		Shavit_PrintToChat(client, "Plugin is fetching data currently, please try again later.");
		return Plugin_Handled;
    }

	int track = Shavit_GetClientTrack(client);
	float time = Shavit_GetClientPB(client, Shavit_GetBhopStyle(client), track);

	if(gA_MapWorldRecord[track].iRankCount == 0 && gB_MapWRCached)
	{
		Shavit_PrintToChat(client, "There are no records in SurfHeaven.");
		return Plugin_Handled;
	}

	if(time > 0.0)
	{
		GetSHSMapRank(client, time, track);     
	}
	else
	{
		char sTrack[32];
		GetTrackName(client, track, sTrack, 32);
		Shavit_PrintToChat(client, "You have no records in %s.", sTrack);
	}

	return Plugin_Handled;
}

public Action Command_SHStageRank(int client, int args)
{
	if(gB_CoolDown[client])
	{
		Shavit_PrintToChat(client, "You just ranking few seconds ago, please wait %s%.1f%s seconds before using this command.",
		gS_ChatStrings.sVariable2, gF_ReadyTime[client] - GetEngineTime(), gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	if(gB_Fetching)
	{
        Shavit_PrintToChat(client, "Plugin is fetching data currently, please try again later.");
        return Plugin_Handled;
    }

	int stage;

	if(args > 0)
	{
		char sArg[8];
		GetCmdArg(1, sArg, 8);
		stage = StringToInt(sArg);
	}
	else
	{
		stage = Shavit_GetClientLastStage(client);      
	}

	if(gA_StageWorldRecord[stage].iRankCount == 0 && gB_StageWRCached)
	{
		Shavit_PrintToChat(client, "There are no records in SurfHeaven.");
		return Plugin_Handled;
	}

	float time = Shavit_GetClientStagePB(client, Shavit_GetBhopStyle(client), Shavit_GetClientLastStage(client));

	if(time > 0.0)
	{
		GetSHStageRank(client, time, stage);     
	}
	else
	{
		Shavit_PrintToChat(client, "You have no records in Stage %d.", stage);
	}

	return Plugin_Handled;
}

public Action Timer_CacheWorldRecord(Handle timer)
{
	if(!gB_Fetching)
	{
		if(!gB_MapWRCached)
		{
			CacheWorldRecord(gS_Map);
		}
		else if(!gB_StageWRCached)
		{
			CacheStageWorldRecord(gS_Map);
		}

		gI_RequestTimes = gI_RequestTimes + 1;
	}

	if(gI_RequestTimes > gCV_MaxRequest.IntValue || (gB_MapWRCached && gB_StageWRCached))
	{
		gB_CacheFail = !(gB_MapWRCached && gB_StageWRCached);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
	gB_Fetching = false;
	gI_RequestTimes = 0;
	
	if (!StrEqual(gS_Map, gS_PreviousMap))
	{
		ResetWRCache();
		CreateTimer(gCV_RetryInterval.FloatValue, Timer_CacheWorldRecord, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnMapEnd()
{
	gS_PreviousMap = gS_Map;
}

public void OnClientPutInServer(int client)
{
	float cd = gF_ReadyTime[client] - GetEngineTime();
	gB_CoolDown[client] = cd > 0.1;

	if(IsValidHandle(gH_CoolDown[client]))
	{
		delete gH_CoolDown[client];
	}

	if(gB_CoolDown[client])
	{
		CreateTimer(cd, Timer_CoolDown, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void ResetWRCache()
{
	wrinfo_t empty_cache;
	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		gA_MapWorldRecord[i] = empty_cache;
	}

	for(int j = 1; j < MAX_STAGES; j++)
	{
		gA_StageWorldRecord[j] = empty_cache;
	}

	gB_MapWRCached = false;
	gB_StageWRCached = false;
	gB_CacheFail = false;
}

public void CacheStageWorldRecord(const char[] map)
{
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_STAGERECORD_URL, map);
	gB_Fetching = true;
	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60; // in seconds
	request.Get(CacheStageWorldRecord_Callback);
}

public void CacheWorldRecord(const char[] map)
{
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_MAPRECORD_URL, map);
	gB_Fetching = true;
	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60; // in seconds
	request.Get(CacheMapWorldRecord_Callback);
}

public void CacheMapWorldRecord_Callback(HTTPResponse response, any data, const char[] error)
{
	if(response.Status != HTTPStatus_OK)
	{
		LogError("Fail to fetch map records info from surf heaven. Reason: %s", error);
		gB_Fetching = false;
		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iRank = record.GetInt("rank");
		int iTrack = record.GetInt("track");

		gA_MapWorldRecord[iTrack].iRankCount++;

		if (iRank == 1)
		{
			if(iTrack <= TRACKS_SIZE)
			{
				gA_MapWorldRecord[iTrack].fTime = record.GetFloat("time");
				record.GetString("name", gA_MapWorldRecord[iTrack].sName, sizeof(wrinfo_t::sName));
			}
		}

		delete record;
	}

	delete array;

	gB_MapWRCached = true;

	CacheStageWorldRecord(gS_Map);
}

public void CacheStageWorldRecord_Callback(HTTPResponse response, any data, const char[] error)
{
	if(response.Status != HTTPStatus_OK)
	{
		LogError("Fail to fetch stage records from surf heaven. Reason: %s", error);
		gB_Fetching = false;
		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iRank = record.GetInt("rank");
		int iStage = record.GetInt("stage");

		gA_StageWorldRecord[iStage].iRankCount++;

		if (iRank == 1)
		{
			if(iStage <= MAX_STAGES)
			{
				gA_StageWorldRecord[iStage].fTime = record.GetFloat("time");
				record.GetString("name", gA_StageWorldRecord[iStage].sName, sizeof(wrinfo_t::sName));
			}
		}

		delete record;
	}

	delete array;

	gB_StageWRCached = true;
	gB_Fetching = false;
}

public int Native_GetSHMapRecordTime(Handle handler, int numParams)
{
	int iTrack = GetNativeCell(1);

	if(iTrack < 0 || iTrack > TRACKS_SIZE)
	{
		return view_as<int>(0.0);
	}
    
	if(gB_MapWRCached)
	{
		return view_as<int>(gA_MapWorldRecord[iTrack].fTime);
	}
	else if(!gB_CacheFail)
	{
		return view_as<int>(-1.0);
	}

	return view_as<int>(0.0);
}

public int Native_GetSHMapRecordName(Handle handler, int numParams)
{
	int iTrack = GetNativeCell(1);

	if(iTrack < 0 || iTrack > TRACKS_SIZE)
	{
		SetNativeString(2, "None", GetNativeCell(3));
		return 0;
	}

	if(gB_MapWRCached)
	{
		SetNativeString(2, gA_MapWorldRecord[iTrack].sName, GetNativeCell(3));
	}
	else if(!gB_CacheFail)
	{
		SetNativeString(2, "Loading...", GetNativeCell(3));
	}
	else
	{
		SetNativeString(2, "None", GetNativeCell(3));
	}

	return 0;
}

public int Native_GetSHStageRecordTime(Handle handler, int numParams)
{
	int iStage = GetNativeCell(1);

	if(iStage < 1 || iStage > MAX_STAGES)
	{
		return view_as<int>(0.0);
	}
    
	if(gB_StageWRCached)
	{
		return view_as<int>(gA_StageWorldRecord[iStage].fTime)        
	}
	else if(!gB_CacheFail)
	{
		return view_as<int>(-1.0);
	}

	return view_as<int>(0.0);
}

public int Native_GetSHStageRecordName(Handle handler, int numParams)
{
	int iStage = GetNativeCell(1);

	if(iStage < 1 || iStage > MAX_STAGES)
	{
		SetNativeString(2, "None", GetNativeCell(3));
		return 0;
    }

	if(gB_StageWRCached)
	{
		SetNativeString(2, gA_StageWorldRecord[iStage].sName, GetNativeCell(3));
	}
	else if(!gB_CacheFail)
	{
		SetNativeString(2, "Loading...", GetNativeCell(3));
	}
	else
	{
		SetNativeString(2, "None", GetNativeCell(3));
	}

	return 0;
}

public void GetSHSMapRank(int client, float time, int track)
{
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_MAPRECORD_URL, gS_Map);

	gB_Fetching = true;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(time);
	pack.WriteCell(track);

	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60; 
	request.Get(GetSHMapRank_Callback, pack);
}

public void GetSHMapRank_Callback(HTTPResponse response, DataPack pack, const char[] error)
{
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	float time = pack.ReadCell();
	int track = pack.ReadCell();
	delete pack;

	if(response.Status != HTTPStatus_OK)
	{
		gB_Fetching = false;
		Shavit_PrintToChat(client, "Failed to retrieve ranking from SurfHeaven.");

		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	int maxrank = array.Length;
	int minrank = 1;

	int rank;

	if (time < gA_MapWorldRecord[track].fTime)
	{
		CallOnFinishRanking(client, track, 0, 1, time);
		delete array;
		return;
	}

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iTrack = record.GetInt("track");
		
		if (track == iTrack)
		{
			float fTime = record.GetFloat("time");
			int iRank = record.GetInt("rank");

			if (iRank > maxrank || iRank < minrank)
			{
				delete record;
				continue;
			}
			else if(maxrank - 1 == minrank)
			{
				CallOnFinishRanking(client, track, 0, maxrank, time);
				delete record;
				delete array;
				return;
			}

			if(fTime < time)
			{
				minrank = iRank;
			}
			else if(fTime > time)
			{
				maxrank = iRank;
			}
			else if(time == fTime)
			{
				CallOnFinishRanking(client, track, 0, iRank, time);
				delete record;
				delete array;
				return;
			}
		}

		delete record;
	}

	rank = minrank + 1;
	CallOnFinishRanking(client, track, 0, rank, time);
	delete array;
}

public void GetSHStageRank(int client, float time, int stage)
{
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_STAGERECORD_URL, gS_Map);

	gB_Fetching = true;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(time);
	pack.WriteCell(stage);

	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60;
	request.Get(GetSHStageRank_Callback, pack);
}

public void GetSHStageRank_Callback(HTTPResponse response, DataPack pack, const char[] error)
{
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	float time = pack.ReadCell();
	int stage = pack.ReadCell();
	delete pack;

	if(response.Status != HTTPStatus_OK)
	{
		gB_Fetching = false;
		Shavit_PrintToChat(client, "Failed to retrieve ranking from SurfHeaven.");

		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	int maxrank = array.Length;
	int minrank = 1;

	int rank;

	if (time < gA_StageWorldRecord[stage].fTime)
	{
		CallOnFinishRanking(client, Track_Main, stage, 1, time);
		delete array;
	}

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iStage = record.GetInt("stage");
		
		if (stage == iStage)
		{
			float fTime = record.GetFloat("time");
			int iRank = record.GetInt("rank");

			if (iRank > maxrank || iRank < minrank)
			{
				delete record;
				continue;
			}
			else if(maxrank - 1 == minrank)
			{
				CallOnFinishRanking(client, Track_Main, stage, maxrank, time);
				delete record;
				delete array;
				return;
			}

			if(fTime < time)
			{
				minrank = iRank;
			}
			else if(fTime > time)
			{
				maxrank = iRank;
			}
			else if(time == fTime)
			{
				CallOnFinishRanking(client, Track_Main, stage, iRank, time);
				delete record;
				delete array;
				return;
			}
		}

		delete record;
	}

	rank = minrank + 1;
	CallOnFinishRanking(client, Track_Main, stage, rank, time);
	delete array;
}

public void CallOnFinishRanking(int client, int track, int stage, int rank, float time)
{
	gB_Fetching = false;
	gB_CoolDown[client] = true;

	if (IsValidHandle(gH_CoolDown[client]))
	{
		delete gH_CoolDown[client];			
	}

	gF_ReadyTime[client] = gCV_RankingCoolDown.FloatValue + GetEngineTime();
	gH_CoolDown[client] = CreateTimer(gCV_RankingCoolDown.FloatValue, Timer_CoolDown, client, TIMER_FLAG_NO_MAPCHANGE);

	char sTrack[32];
	int iRankCount;

	if(track == 0 && stage > 0)
	{
		iRankCount = gA_StageWorldRecord[stage].iRankCount;
		FormatEx(sTrack, 32, "Stage %d", stage);
	}
	else
	{
		iRankCount = gA_MapWorldRecord[track].iRankCount;
		GetTrackName(client, track, sTrack, 32);
	}

	char sTime[16];
	FormatSeconds(time, sTime, 16, true);

	Shavit_PrintToChat(client, "You ranked %s#%d%s (%s%d%s) with a time of %s%s%s %s[%s]%s in SurfHeaven.", 
		gS_ChatStrings.sVariable, rank, gS_ChatStrings.sText, 
		gS_ChatStrings.sVariable, iRankCount, gS_ChatStrings.sText, 
		gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
		gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
}

public Action Timer_CoolDown(Handle timer, int client)
{
	gH_CoolDown[client] = null;
	gB_CoolDown[client] = false;

	return Plugin_Stop;
}