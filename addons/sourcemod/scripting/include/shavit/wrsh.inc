#if defined _shavit_wrsh_included
	#endinput
#endif
#define _shavit_wrsh_included

#define SH_MAPRECORD_URL "https://surfheaven.eu/api/records/"
#define SH_STAGERECORD_URL "https://surfheaven.eu/api/stages/"

enum struct wrinfo_t
{
	float fTime;
	char sName[32];
	char sDate[16];
	int iRankCount;
}

/**
 * Retrieves the top record's time of specific track in surf heaven if there are record exist.
 * 
 * @param track         Track number.
 * 
 * @return              The time of top record in surf heaven, -1.0 if fetching records.
 */
native float Shavit_GetSHMapRecordTime(int track);

/**
 * Retrieves the top record's time of specific stage in surf heaven if there are record exist.
 * 
 * @param track         Track number.
 * @param output        Reference to the name variable.
 * @param size          Size of string buffer.
 * 
 * @noreturn
 */
native void Shavit_GetSHMapRecordName(int track, const char[] output, int size);

/**
 * Retrieves the top record's time of specific stage in surf heaven if there are record exist.
 * 
 * @param stage         Stage number.
 * 
 * @return              The time of top record in surf heaven, -1.0 if fetching records.
 */
native float Shavit_GetSHStageRecordTime(int stage);

/**
 * Retrieves the top record's runner of specific stage in surf heaven if there are record exist.
 * 
 * @param stage         Stage number.
 * @param output        Reference to the name variable.
 * @param size          Size of string buffer.
 * 
 * @noreturn
 */
native void Shavit_GetSHStageRecordName(int stage, const char[] output, int size);


public SharedPlugin __pl_shavit_wrsh =
{
	name = "shavit-wrsh",
	file = "shavit-wrsh.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_wrsh_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetSHMapRecordTime");
	MarkNativeAsOptional("Shavit_GetSHMapRecordName");
	MarkNativeAsOptional("Shavit_GetSHStageRecordTime");
	MarkNativeAsOptional("Shavit_GetSHStageRecordName");
}
#endif