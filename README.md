# Surf timer base on shavit timer (CS:S ONLY)

## Main Changes

1. Implemented storeage of StageCP Personal Best.
    - show time difference to PB/WR when player reached next stage
    - add HUD option "stage"
2. Add center speed HUD.
    - fully color, postion and refresh rate customize
    - show speed difference
    - get color by player's strafe gain
3. Timer will start when player run on a single stage now.


# Change logs

## shavit-core
	
    - Add iLastStage to timer_snapshot_t: int variable, client's last reached stage zone number  
    - Add fStageStartTime to timer_snapshot_t: float variable, assign to client's current time when leave a stage zone/start zone.
    - Add bStageTimeValid to timer_snapshot_t: bool variable, assign when client leave a stage zone, check if client's velocity greater than prespeed limit
    - Add bOnlyStageMode to timer_snapshot_t: bool variable, timer will start in a stage zone if bOnlyStageMode is true.
    - Set player's last stage (gI_LastStage iLastStage) to 1 when StartTimer() called
    - Assign iLastStage fStageStartTime bStageTimeValid bOnlyStageMode when BuildSnapshot() called

### APIs

    - Add native Shavit_SetClientTrack
    - Add native Shavit_IsOnlyStageMode
    - Add native Shavit_SetOnlyStageMode
    - Add native Shavit_FinishStage
    - Add forward Shavit_OnFinishStage
    - Add forward Shavit_OnFinishStagePre
    - Change forward Shavit_OnRestart(int client, int track) to Shavit_OnRestart(int client, int track, bool tostartzone)

## shavit-checkpoint
    - Some change adapte to shavit-core's changes

## shavit-hud

    - Delete TopLeftHUD
    - Now WR/PB and Style are showing on Key Hint
    - Add iCurrentStage iStageCount iZoneStage fStageTime bInsideStageZone to huddata_t
    - Add ZoneHUD_StageStart to ZoneHUD
    - Rework the logic of function AddHUDToBuffer_Source2013
    - Add stage message to Center HUD
    - Add stage time message to Center HUD
    - Show start/end zone's track in ZoneHUD (eg. In Main Start)
    - Now main timer show as full min:sec instead dynamic format

## shavit-misc

    - Adapte bInStart to only stage mode when player inside a stage start zone
    - Now apply prespeed limit to a stage zone.

## shavit-replay-recorder

    - Adapte bInStart to only stage mode when player inside a stage start zone
    - Now preframes will reset when player in stage start while bOnlyStageMode is true

## shavit-zones

    - Add new global timer_snapshot_t struct gA_StageStartTimer
    - Add new command "sm_back"
    - Add new logic to function Command_Stages
    - Add new logic to function Shavit_OnRestart allow player teleport to current stage start zone while running on a single stage
    - Call Shavit_StartTimer when player entered a stage zone while bOnlyStageMode is true
    - Call Shavit_FinishStage when player entered stage zone which stage number equals gI_LastStage + 1
    - Assign 1 to gI_LastStage when player entered a start zone. (start zone recognize as a stage 1 zone)

### APIs

    - Delete forward Shavit_OnStageMessage
    - Add forward Shavit_OnReachNextStage
    - Add native Shavit_SetClientLastStage
    - Add native Shavit_GetClientStageTime
    - Add native Shavit_GetStageStartInfo
    - Add native Shavit_GetStageStartTime
    - Add native Shavit_SetStageStartTime
    - Add native Shavit_InsideZoneStage
    - Implemente native Shavit_GetStageCount

## shavit-Wr
    - Now plugin is able to load player's stage checkpoint personal best to cache
    - Add logic to Shavit_OnLeaveZone to check if player's prespeed greater than prespeed limit
    - Add logic to Shavit_OnFinish to print message correctly in a situation of first player finish the map.
    - Add new global arrayList gA_StageCP_PB
    - Add new global variable gA_StageReachedTimes
    - Add new global variable gA_StageFinishedTimes
    - Add new global variablegA_StageTimeValid
    - Add new function ResetStagePBCPs
    - Add new function SQL_UpdateStagePBCache_Callback
    - Add new function UpdateClientStagePBCacheOnFinish
    - Change finish message to "<username> finished [<track>] in <time> (<WR diff> | <PB diff>). Rank: <rank> (<style>)"

### APIs

    - Add new native Shavit_GetStageCPWR
    - Add new native Shavit_GetStageCPPB
    - Add new native Shavit_StageTimeValid
    - Add new native Shavit_SetStageTimeValid
    
