#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <tf2attributes>
#include <tf2items>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#include "dayz/dayz_core.inc"

// 글로벌 변수
bool g_bEnabled = true;
bool g_bWaitingPeriod = true;
bool g_bRoundStarted = false;

int g_iMaxHealth = MAX_HEALTH;
int g_iKills[MAXPLAYERS + 1];
int g_iDeaths[MAXPLAYERS + 1];
int g_iKarma[MAXPLAYERS + 1];
float g_fHunger[MAXPLAYERS + 1];
float g_fThirst[MAXPLAYERS + 1];
float g_fStamina[MAXPLAYERS + 1];
bool g_bFirstSpawn[MAXPLAYERS + 1];
bool g_bIsSprinting[MAXPLAYERS + 1];
float g_fDefaultSpeed[MAXPLAYERS + 1];
float g_fLastPosition[MAXPLAYERS + 1][3];
float g_fLastAngles[MAXPLAYERS + 1][3];
bool g_bHasPosition[MAXPLAYERS + 1];
float g_fLastSprintTime[MAXPLAYERS + 1];

// 상태 이상 관련 변수
bool g_bStatusEffects[MAXPLAYERS + 1][3];
float g_fStatusStartTime[MAXPLAYERS + 1][3];
float g_fLastBleedingDamage[MAXPLAYERS + 1];
float g_fWaterStartTime[MAXPLAYERS + 1];
bool g_bInWater[MAXPLAYERS + 1];
int g_iBackupStatusEffects[MAXPLAYERS + 1][3];
bool g_bStatusBackupDone[MAXPLAYERS + 1];

// 데이터 로드 상태
bool g_bDataLoaded[MAXPLAYERS + 1][4];
bool g_bHandledByOtherPlugin[MAXPLAYERS + 1];

// HUD
Handle g_hHudSync = null;

// ConVar
ConVar g_cvKarmaKillHigh;
ConVar g_cvKarmaKillLow;
ConVar g_cvHungerRate;
ConVar g_cvThirstRate;
ConVar g_cvStaminaRate;
ConVar g_cvSprintDrain;
ConVar g_cvWaitTime;
ConVar g_cvMinPlayers;
ConVar g_cvDebugMode;

// 포워드
Handle g_hOnPlayerDataLoaded;
Handle g_hOnPlayerStatusChange;
Handle g_hOnItemPickup;
Handle g_hOnItemDrop;
Handle g_hOnWeaponEquip;
Handle g_hOnStatusEffectApply;
Handle g_hOnStatusEffectRemove;

public Plugin myinfo = {
    name = "TF2 DayZ Mode - Core",
    author = "FinN",
    description = "DayZ Core System for Team Fortress 2",
    version = PLUGIN_VERSION,
    url = "https://steamcommunity.com/profiles/76561198041705012/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    // 네이티브 함수 등록
    CreateNative("DayZ_IsEnabled", Native_IsEnabled);
    CreateNative("DayZ_IsWaitingPeriod", Native_IsWaitingPeriod);
    CreateNative("DayZ_GetPlayerKarma", Native_GetPlayerKarma);
    CreateNative("DayZ_SetPlayerKarma", Native_SetPlayerKarma);
    CreateNative("DayZ_GetPlayerHunger", Native_GetPlayerHunger);
    CreateNative("DayZ_SetPlayerHunger", Native_SetPlayerHunger);
    CreateNative("DayZ_GetPlayerThirst", Native_GetPlayerThirst);
    CreateNative("DayZ_SetPlayerThirst", Native_SetPlayerThirst);
    CreateNative("DayZ_GetPlayerStamina", Native_GetPlayerStamina);
    CreateNative("DayZ_SetPlayerStamina", Native_SetPlayerStamina);
    
    // 포워드 생성
    g_hOnPlayerDataLoaded = CreateGlobalForward("DayZ_OnPlayerDataLoaded", ET_Ignore, Param_Cell);
    g_hOnPlayerStatusChange = CreateGlobalForward("DayZ_OnPlayerStatusChange", ET_Ignore, Param_Cell, Param_Float, Param_Float, Param_Float);
    g_hOnItemPickup = CreateGlobalForward("DayZ_OnItemPickup", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_hOnItemDrop = CreateGlobalForward("DayZ_OnItemDrop", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_hOnWeaponEquip = CreateGlobalForward("DayZ_OnWeaponEquip", ET_Ignore, Param_Cell, Param_Cell, Param_String);
    g_hOnStatusEffectApply = CreateGlobalForward("DayZ_OnStatusEffectApply", ET_Ignore, Param_Cell, Param_Cell);
    g_hOnStatusEffectRemove = CreateGlobalForward("DayZ_OnStatusEffectRemove", ET_Ignore, Param_Cell, Param_Cell);
    
    RegPluginLibrary("dayz_core");
    return APLRes_Success;
}

public void OnPluginStart() {
    // ConVar 생성
    g_cvKarmaKillHigh = CreateConVar("sm_dayz_karma_kill_high", "50", "카르마가 높은 플레이어 처치시 감소량");
    g_cvKarmaKillLow = CreateConVar("sm_dayz_karma_kill_low", "30", "카르마가 낮은 플레이어 처치시 증가량");
    g_cvHungerRate = CreateConVar("sm_dayz_hunger_rate", "0.2", "배고픔 감소율");
    g_cvThirstRate = CreateConVar("sm_dayz_thirst_rate", "0.3", "갈증 감소율");
    g_cvStaminaRate = CreateConVar("sm_dayz_stamina_rate", "5.0", "스태미나 회복률");
    g_cvSprintDrain = CreateConVar("sm_dayz_sprint_drain", "10.0", "스프린트 시 스태미나 감소율");
    g_cvWaitTime = CreateConVar("sm_dayz_wait_time", "10", "라운드 시작 대기 시간");
    g_cvMinPlayers = CreateConVar("sm_dayz_min_players", "1", "게임 시작에 필요한 최소 플레이어 수");
    g_cvDebugMode = CreateConVar("sm_dayz_debug", "0", "디버그 모드 활성화 (1: 켜기, 0: 끄기)", FCVAR_NOTIFY);

    // 명령어 등록
    RegConsoleCmd("sm_dayz", Command_DayzMenu, "메인 메뉴 열기");
    RegConsoleCmd("+sprint", Command_StartSprint, "달리기 시작");
    RegConsoleCmd("-sprint", Command_StopSprint, "달리기 중지");
    RegConsoleCmd("sm_save", Command_SaveMyData, "내 데이터 저장");
    
    // 관리자 명령어
    RegAdminCmd("sm_dayz_debug", Command_DebugMode, ADMFLAG_ROOT, "디버그 모드 켜기/끄기");
    RegAdminCmd("sm_dayz_toggle", Command_TogglePlugin, ADMFLAG_ROOT, "플러그인 켜기/끄기");
    RegAdminCmd("sm_shutdown", Command_ShutdownServer, ADMFLAG_ROOT, "서버를 안전하게 종료");

    // 이벤트 훅
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("teamplay_round_start", Event_TeamplayRoundStart);
    HookEvent("teamplay_waiting_begins", Event_WaitingBegins);
    HookEvent("teamplay_waiting_ends", Event_WaitingEnds);
    HookEvent("player_hurt", Event_PlayerHurt);

    // 명령어 리스너
    AddCommandListener(Command_ShowScoreboard, "+score");
    AddCommandListener(Command_ShowScoreboard, "showscores");
    AddCommandListener(Command_HideScoreboard, "-score");
    AddCommandListener(Command_HideScoreboard, "hidescores");
    AddCommandListener(Command_VoiceMenu, "voicemenu");

    // HUD 초기화
    g_hHudSync = CreateHudSynchronizer();

    // 타이머 생성
    CreateTimer(1.0, Timer_UpdateStatus, _, TIMER_REPEAT);
    CreateTimer(1.0, Timer_CheckGameState, _, TIMER_REPEAT);
    CreateTimer(0.5, Timer_CheckWaterStatus, _, TIMER_REPEAT);

    // 서버 설정
    ServerCommand("tf_bot_quota_mode normal");
    ServerCommand("tf_bot_quota 1");
    ServerCommand("tf_bot_auto_vacate 0");
    ServerCommand("tf_bot_keep_class_after_death 1");
    ServerCommand("tf_bot_join_after_player 0");
    ServerCommand("mp_autoteambalance 0");
    ServerCommand("tf_bot_difficulty 0");

    // 사운드 프리캐시
    PrecacheSound(SOUND_PICKUP);
    PrecacheSound(SOUND_DROP);
    PrecacheSound(SOUND_EAT);
    PrecacheSound(SOUND_DRINK);
    PrecacheSound(EMPTY_WEAPON_SOUND);

    AutoExecConfig(true, "dayz_mode");
}

public void OnClientPutInServer(int client) {
    if (!IsValidClient(client)) return;
    
    // 데이터 로드 상태 초기화
    for (int i = 0; i < 4; i++) {
        g_bDataLoaded[client][i] = false;
    }
    
    // 상태 이상 초기화
    for (int i = 0; i < 3; i++) {
        g_bStatusEffects[client][i] = false;
        g_fStatusStartTime[client][i] = 0.0;
        g_iBackupStatusEffects[client][i] = 0;
    }
    g_fLastBleedingDamage[client] = 0.0;
    g_fWaterStartTime[client] = 0.0;
    g_bInWater[client] = false;
    g_bStatusBackupDone[client] = false;
    
    // OnTakeDamage 훅 추가
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    
    g_bFirstSpawn[client] = true;
    g_bHasPosition[client] = false;
    g_bIsSprinting[client] = false;
    g_fLastSprintTime[client] = 0.0;
    g_bHandledByOtherPlugin[client] = false;
    
    CreateTimer(1.0, Timer_GetDefaultSpeed, GetClientUserId(client));
    ResetPlayerStatus(client);
    
    PrintToChat(client, "\x04[데이즈]\x01 플레이어 데이터를 초기화했습니다.");
}

public void OnClientDisconnect(int client) {
    if (IsValidClient(client)) {
        for (int i = 0; i < 4; i++) {
            g_bDataLoaded[client][i] = false;
        }
    }
}

// 네이티브 함수 구현
public int Native_IsEnabled(Handle plugin, int numParams) {
    return g_bEnabled;
}

public int Native_IsWaitingPeriod(Handle plugin, int numParams) {
    return g_bWaitingPeriod;
}

public int Native_GetPlayerKarma(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    return g_iKarma[client];
}

public int Native_SetPlayerKarma(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int karma = GetNativeCell(2);
    g_iKarma[client] = karma;
    return 0;
}

public int Native_GetPlayerHunger(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    return view_as<int>(g_fHunger[client]);
}

public int Native_SetPlayerHunger(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    float hunger = GetNativeCell(2);
    g_fHunger[client] = hunger;
    return 0;
}

public int Native_GetPlayerThirst(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    return view_as<int>(g_fThirst[client]);
}

public int Native_SetPlayerThirst(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    float thirst = GetNativeCell(2);
    g_fThirst[client] = thirst;
    return 0;
}

public int Native_GetPlayerStamina(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    return view_as<int>(g_fStamina[client]);
}

public int Native_SetPlayerStamina(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    float stamina = GetNativeCell(2);
    g_fStamina[client] = stamina;
    return 0;
}

// 이벤트 핸들러
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    if (g_bWaitingPeriod) {
        TF2_SetPlayerClass(client, TFClass_Sniper);
        PrintHintText(client, "대기 시간입니다. 게임 시작까지 기다려주세요.");
        return;
    }
    
    if (g_bFirstSpawn[client]) {
        g_bFirstSpawn[client] = false;
        ResetPlayerStatus(client);
        TF2_SetPlayerClass(client, TFClass_Sniper);
        SetEntityHealth(client, g_iMaxHealth);
    } else if (!g_bWaitingPeriod && g_bHasPosition[client]) {
        TF2_SetPlayerClass(client, TFClass_Sniper);
        SetEntityHealth(client, g_iMaxHealth);
        
        DataPack pack;
        CreateDataTimer(0.5, Timer_TeleportToSavedPosition, pack, TIMER_FLAG_NO_MAPCHANGE);
        pack.WriteCell(GetClientUserId(client));
        pack.WriteFloat(g_fLastPosition[client][0]);
        pack.WriteFloat(g_fLastPosition[client][1]);
        pack.WriteFloat(g_fLastPosition[client][2]);
        pack.WriteFloat(g_fLastAngles[client][0]);
        pack.WriteFloat(g_fLastAngles[client][1]);
        pack.WriteFloat(g_fLastAngles[client][2]);
    }
    
    // 포워드 호출
    Call_StartForward(g_hOnPlayerDataLoaded);
    Call_PushCell(client);
    Call_Finish();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    
    if (!IsValidClient(victim)) return;
    
    float pos[3], ang[3];
    GetClientAbsOrigin(victim, pos);
    GetClientEyeAngles(victim, ang);
    
    g_fHunger[victim] = DEFAULT_HUNGER;
    g_fThirst[victim] = DEFAULT_THIRST;
    g_fStamina[victim] = DEFAULT_STAMINA;
    g_fLastPosition[victim] = pos;
    g_fLastAngles[victim] = ang;
    g_bHasPosition[victim] = true;
    
    g_iDeaths[victim]++;
    
    if (IsValidClient(attacker) && attacker != victim) {
        g_iKills[attacker]++;
        
        if (g_iKarma[victim] >= DEFAULT_KARMA) {
            int karmaLoss = g_cvKarmaKillHigh.IntValue;
            g_iKarma[attacker] -= karmaLoss;
            PrintToChat(attacker, "\x04[데이즈]\x01 착한 플레이어를 죽여 카르마가 감소했습니다. (-%d)", karmaLoss);
        } else {
            int karmaGain = g_cvKarmaKillLow.IntValue;
            g_iKarma[attacker] += karmaGain;
            PrintToChat(attacker, "\x04[데이즈]\x01 나쁜 플레이어를 처치해 카르마가 증가했습니다. (+%d)", karmaGain);
        }
    }
    
    // 상태이상 완전 초기화
    for (int i = 0; i < 3; i++) {
        g_bStatusEffects[victim][i] = false;
        g_fStatusStartTime[victim][i] = 0.0;
        g_iBackupStatusEffects[victim][i] = 0;
    }
    g_fLastBleedingDamage[victim] = 0.0;
    g_fWaterStartTime[victim] = 0.0;
    g_bInWater[victim] = false;
    g_bStatusBackupDone[victim] = false;
    
    g_fLastPosition[victim] = view_as<float>({0.0, 0.0, 0.0});
    g_fLastAngles[victim] = view_as<float>({0.0, 0.0, 0.0});
    g_bHasPosition[victim] = false;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    if (g_bRoundStarted) return;
    g_bRoundStarted = true;
    g_bWaitingPeriod = false;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    g_bWaitingPeriod = true;
    g_bRoundStarted = false;
}

public void Event_TeamplayRoundStart(Event event, const char[] name, bool dontBroadcast) {
    g_bWaitingPeriod = true;
    CreateTimer(g_cvWaitTime.FloatValue, Timer_StartRound);
}

public void Event_WaitingBegins(Event event, const char[] name, bool dontBroadcast) {
}

public void Event_WaitingEnds(Event event, const char[] name, bool dontBroadcast) {
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int damage = event.GetInt("damageamount");
    
    if (!IsValidClient(victim) || !IsValidClient(attacker)) return;
    if (victim == attacker) return;
    
    // 총상으로 인한 출혈 (15% 확률)
    if (damage >= 20 && !g_bStatusEffects[victim][view_as<int>(STATUS_BLEEDING) - 1]) {
        if (GetRandomInt(1, 100) <= 15) {
            ApplyStatusEffect(victim, STATUS_BLEEDING);
            PrintToChat(victim, "\x04[데이즈]\x01 피격으로 인해 출혈이 발생했습니다!");
        }
    }
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
    if (!IsValidClient(victim) || !IsPlayerAlive(victim)) return Plugin_Continue;
    
    // 낙하 데미지 감지
    if (damagetype & DMG_FALL && damage >= 30.0) {
        // 25% 확률로 골절
        if (GetRandomInt(1, 100) <= 25 && !g_bStatusEffects[victim][view_as<int>(STATUS_FRACTURE) - 1]) {
            ApplyStatusEffect(victim, STATUS_FRACTURE);
            PrintToChat(victim, "\x04[데이즈]\x01 낙하로 인해 골절이 발생했습니다!");
        }
    }
    
    return Plugin_Continue;
}

public Action Command_VoiceMenu(int client, const char[] command, int args) {
    if (!IsValidClient(client) || !IsPlayerAlive(client) || g_bWaitingPeriod) {
        return Plugin_Continue;
    }
    
    if (args >= 2) {
        char arg1[8], arg2[8];
        GetCmdArg(1, arg1, sizeof(arg1));
        GetCmdArg(2, arg2, sizeof(arg2));
        
        // "voicemenu 0 0" = 메딕 호출 (기본 E키)
        if (StrEqual(arg1, "0") && StrEqual(arg2, "0")) {
            // 다른 플러그인에서 처리하도록 전달
            g_bHandledByOtherPlugin[client] = true;
            return Plugin_Continue;
        }
    }
    
    return Plugin_Continue;
}

// 타이머 함수
public Action Timer_UpdateStatus(Handle timer) {
    if (!g_bEnabled || g_bWaitingPeriod) return Plugin_Continue;
    
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidClient(i) || !IsPlayerAlive(i)) continue;
        
        // 기존 배고픔/갈증/스태미나 처리
        float oldHunger = g_fHunger[i];
        float oldThirst = g_fThirst[i];
        float oldStamina = g_fStamina[i];
        
        g_fHunger[i] = FloatMax(0.0, g_fHunger[i] - g_cvHungerRate.FloatValue);
        g_fThirst[i] = FloatMax(0.0, g_fThirst[i] - g_cvThirstRate.FloatValue);
        
        if (g_bIsSprinting[i]) {
            g_fStamina[i] = FloatMax(0.0, g_fStamina[i] - g_cvSprintDrain.FloatValue);
            
            if (g_fStamina[i] <= SPRINT_MIN_STAMINA) {
                Command_StopSprint(i, 0);
            }
        } else {
            float currentTime = GetGameTime();
            if (currentTime - g_fLastSprintTime[i] >= SPRINT_COOLDOWN) {
                // 감기 상태가 아닐 때만 스태미나 회복
                if (!g_bStatusEffects[i][view_as<int>(STATUS_COLD) - 1]) {
                    g_fStamina[i] = FloatMin(DEFAULT_STAMINA, g_fStamina[i] + g_cvStaminaRate.FloatValue);
                } else {
                    g_fStamina[i] = 0.0; // 감기 상태면 스태미나 0 고정
                }
            }
        }
        
        // 상태 변화 포워드 호출
        if (oldHunger != g_fHunger[i] || oldThirst != g_fThirst[i] || oldStamina != g_fStamina[i]) {
            Call_StartForward(g_hOnPlayerStatusChange);
            Call_PushCell(i);
            Call_PushFloat(g_fHunger[i]);
            Call_PushFloat(g_fThirst[i]);
            Call_PushFloat(g_fStamina[i]);
            Call_Finish();
        }
        
        // 상태이상 처리
        ProcessStatusEffects(i);
        
        // 체력 감소 처리
        int health = GetClientHealth(i);
        
        if (g_fHunger[i] <= 0.0 || g_fThirst[i] <= 0.0) {
            int newHealth = health - 5;
            
            if (newHealth <= 0) {
                ForcePlayerSuicide(i);
                if (g_fHunger[i] <= 0.0) {
                    PrintToChat(i, "\x04[데이즈]\x01 배고픔으로 인해 사망했습니다.");
                } else {
                    PrintToChat(i, "\x04[데이즈]\x01 갈증으로 인해 사망했습니다.");
                }
            } else {
                SetEntityHealth(i, newHealth);
                
                if (g_fHunger[i] <= 0.0) {
                    PrintHintText(i, "※ 경고: 배고픔으로 인해 체력이 감소하고 있습니다!");
                } else {
                    PrintHintText(i, "※ 경고: 갈증으로 인해 체력이 감소하고 있습니다!");
                }
            }
        }
        
        UpdatePlayerHUD(i);
    }
    
    return Plugin_Continue;
}

public Action Timer_CheckWaterStatus(Handle timer) {
    if (!g_bEnabled || g_bWaitingPeriod) return Plugin_Continue;
    
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsValidClient(client) || !IsPlayerAlive(client)) continue;
        
        // 플레이어가 물속에 있는지 확인
        float pos[3];
        GetClientAbsOrigin(client, pos);
        
        bool inWaterNow = false;
        bool isFractured = g_bStatusEffects[client][view_as<int>(STATUS_FRACTURE) - 1];
        float speed = GetEntPropFloat(client, Prop_Data, "m_flMaxspeed");
        
        // 골절 상태가 아닐 때: 위치 + 속도로 판단
        if (!isFractured) {
            if (pos[2] < 100.0 && speed < 200.0) {
                inWaterNow = true;
            }
        }
        // 골절 상태일 때: 위치만으로 판단 (더 엄격)
        else {
            if (pos[2] < 50.0) {
                inWaterNow = true;
            }
        }
        
        if (inWaterNow && !g_bInWater[client]) {
            // 물에 들어감
            g_bInWater[client] = true;
            g_fWaterStartTime[client] = GetGameTime();
        }
        else if (!inWaterNow && g_bInWater[client]) {
            // 물에서 나옴
            g_bInWater[client] = false;
            g_fWaterStartTime[client] = 0.0;
        }
        else if (inWaterNow && g_bInWater[client]) {
            // 계속 물속에 있음
            float waterTime = GetGameTime() - g_fWaterStartTime[client];
            
            // 이미 감기에 걸린 상태가 아니라면 체크
            if (!g_bStatusEffects[client][view_as<int>(STATUS_COLD) - 1]) {
                // 30초 이상 물속에 있으면 10% 확률로 감기 걸림
                if (waterTime >= 30.0) {
                    if (GetRandomInt(1, 100) <= 10) {
                        ApplyStatusEffect(client, STATUS_COLD);
                    } else {
                        // 확률에 걸리지 않았다면 시간 리셋하여 다시 기회 제공
                        g_fWaterStartTime[client] = GetGameTime();
                    }
                }
            }
        }
    }
    
    return Plugin_Continue;
}

public Action Timer_CheckGameState(Handle timer) {
    if (!g_bEnabled) return Plugin_Continue;
    
    int playerCount = GetClientCount(true);
    if (playerCount < g_cvMinPlayers.IntValue) {
        g_bWaitingPeriod = true;
        PrintHintTextToAll("최소 %d명의 플레이어가 필요합니다", g_cvMinPlayers.IntValue);
    }
    
    return Plugin_Continue;
}

public Action Timer_StartRound(Handle timer) {
    if (GetClientCount(true) >= g_cvMinPlayers.IntValue || g_cvMinPlayers.IntValue <= 1) {
        g_bWaitingPeriod = false;
    } else {
        CreateTimer(15.0, Timer_StartRound);
    }
    return Plugin_Stop;
}

public Action Timer_GetDefaultSpeed(Handle timer, any data) {
    int client = GetClientOfUserId(data);
    if (IsValidClient(client)) {
        g_fDefaultSpeed[client] = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
    }
    return Plugin_Stop;
}

public Action Timer_TeleportToSavedPosition(Handle timer, DataPack pack) {
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    if (!IsValidClient(client) || !IsPlayerAlive(client)) return Plugin_Stop;
    
    float pos[3], ang[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    ang[0] = pack.ReadFloat();
    ang[1] = pack.ReadFloat();
    ang[2] = pack.ReadFloat();
    
    TeleportEntity(client, pos, ang, NULL_VECTOR);
    
    return Plugin_Stop;
}

// 명령어 핸들러
public Action Command_DayzMenu(int client, int args) {
    if (!IsValidClient(client)) return Plugin_Handled;
    PrintToChat(client, "\x04[데이즈]\x01 메뉴는 다른 플러그인에서 제공됩니다.");
    return Plugin_Handled;
}

public Action Command_StartSprint(int client, int args) {
    if (!IsValidClient(client) || !IsPlayerAlive(client) || g_bWaitingPeriod)
        return Plugin_Handled;
    
    float currentTime = GetGameTime();
    if (currentTime - g_fLastSprintTime[client] < SPRINT_COOLDOWN) {
        PrintHintText(client, "아직 달리기를 사용할 수 없습니다!");
        return Plugin_Handled;
    }
    
    if (g_fStamina[client] <= SPRINT_MIN_STAMINA) {
        PrintHintText(client, "스태미나가 부족합니다!");
        return Plugin_Handled;
    }
    
    g_bIsSprinting[client] = true;
    SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", GetEntPropFloat(client, Prop_Data, "m_flMaxspeed") * SPRINT_SPEED_MULTIPLIER);
    return Plugin_Handled;
}

public Action Command_StopSprint(int client, int args) {
    if (!IsValidClient(client)) return Plugin_Handled;
    
    if (g_bIsSprinting[client]) {
        g_bIsSprinting[client] = false;
        SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", GetEntPropFloat(client, Prop_Data, "m_flMaxspeed") / SPRINT_SPEED_MULTIPLIER);
        g_fLastSprintTime[client] = GetGameTime();
    }
    return Plugin_Handled;
}

public Action Command_SaveMyData(int client, int args) {
    if (!IsValidClient(client)) return Plugin_Handled;
    
    if (IsPlayerAlive(client)) {
        float pos[3], ang[3];
        GetClientAbsOrigin(client, pos);
        GetClientEyeAngles(client, ang);
        g_fLastPosition[client] = pos;
        g_fLastAngles[client] = ang;
        g_bHasPosition[client] = true;
    }
    
    PrintToChat(client, "\x04[데이즈]\x01 데이터가 저장되었습니다.");
    return Plugin_Handled;
}

public Action Command_DebugMode(int client, int args) {
    if (!IsValidAdmin(client)) {
        PrintToChat(client, "\x04[데이즈]\x01 이 명령어는 관리자만 사용할 수 있습니다.");
        return Plugin_Handled;
    }
    
    bool newValue = !g_cvDebugMode.BoolValue;
    g_cvDebugMode.SetBool(newValue);
    
    PrintToChat(client, "\x04[데이즈]\x01 디버그 모드가 %s되었습니다.", newValue ? "활성화" : "비활성화");
    PrintToServer("[데이즈] 디버그 모드 %s (관리자: %N)", newValue ? "켜짐" : "꺼짐", client);
    
    return Plugin_Handled;
}

public Action Command_TogglePlugin(int client, int args) {
    if (!IsValidAdmin(client)) return Plugin_Handled;
    g_bEnabled = !g_bEnabled;
    PrintToChatAll("\x04[데이즈]\x01 플러그인이 %s되었습니다.", g_bEnabled ? "활성화" : "비활성화");
    return Plugin_Handled;
}

public Action Command_ShutdownServer(int client, int args) {
    if (!IsValidAdmin(client)) {
        PrintToChat(client, "\x04[데이즈]\x01 이 명령어는 관리자만 사용할 수 있습니다.");
        return Plugin_Handled;
    }
    
    PrintToChatAll("\x04[데이즈]\x01 서버가 10초 후에 종료됩니다.");
    CreateTimer(10.0, Timer_ShutdownServer);
    
    return Plugin_Handled;
}

public Action Timer_ShutdownServer(Handle timer) {
    ServerCommand("quit");
    return Plugin_Stop;
}

public Action Command_ShowScoreboard(int client, const char[] command, int args) {
    if (!IsValidClient(client) || !g_bEnabled) {
        return Plugin_Continue;
    }
    
    if (g_bHandledByOtherPlugin[client]) {
        g_bHandledByOtherPlugin[client] = false;
        return Plugin_Continue;
    }
    
    return Plugin_Handled;
}

public Action Command_HideScoreboard(int client, const char[] command, int args) {
    if (!IsValidClient(client) || !g_bEnabled) {
        return Plugin_Continue;
    }
    
    return Plugin_Handled;
}

// 유틸리티 함수
void ProcessStatusEffects(int client) {
    // 출혈 효과
    if (g_bStatusEffects[client][view_as<int>(STATUS_BLEEDING) - 1]) {
        float currentTime = GetGameTime();
        if (currentTime - g_fLastBleedingDamage[client] >= 3.0) {
            int currentHealth = GetClientHealth(client);
            int newHealth = currentHealth - 5;
            
            if (newHealth <= 0) {
                ForcePlayerSuicide(client);
                PrintToChat(client, "\x04[데이즈]\x01 출혈로 인해 사망했습니다.");
            } else {
                SetEntityHealth(client, newHealth);
                PrintHintText(client, "※ 출혈 중: 체력이 감소하고 있습니다! 붕대가 필요합니다.");
            }
            
            g_fLastBleedingDamage[client] = currentTime;
        }
    }
    
    // 골절 효과 경고
    if (g_bStatusEffects[client][view_as<int>(STATUS_FRACTURE) - 1]) {
        static float lastFractureWarning[MAXPLAYERS + 1];
        float currentTime = GetGameTime();
        if (currentTime - lastFractureWarning[client] >= 10.0) {
            PrintHintText(client, "※ 골절 상태: 이동속도가 감소했습니다! 부목이 필요합니다.");
            lastFractureWarning[client] = currentTime;
        }
    }
    
    // 감기 효과 경고
    if (g_bStatusEffects[client][view_as<int>(STATUS_COLD) - 1]) {
        static float lastColdWarning[MAXPLAYERS + 1];
        float currentTime = GetGameTime();
        if (currentTime - lastColdWarning[client] >= 15.0) {
            PrintHintText(client, "※ 감기 상태: 스태미나를 회복할 수 없습니다! 감기약이 필요합니다.");
            lastColdWarning[client] = currentTime;
        }
    }
}

void ApplyStatusEffect(int client, StatusEffect effect) {
    if (!IsValidClient(client)) return;
    
    int effectIndex = view_as<int>(effect) - 1;
    if (effectIndex < 0 || effectIndex >= 3) return;
    
    if (!g_bStatusEffects[client][effectIndex]) {
        g_bStatusEffects[client][effectIndex] = true;
        g_fStatusStartTime[client][effectIndex] = GetGameTime();
        
        char effectName[32];
        GetStatusEffectName(effect, effectName, sizeof(effectName));
        
        PrintToChat(client, "\x04[데이즈]\x01 %s 상태에 걸렸습니다!", effectName);
        
        // 포워드 호출
        Call_StartForward(g_hOnStatusEffectApply);
        Call_PushCell(client);
        Call_PushCell(view_as<int>(effect));
        Call_Finish();
    }
}

void RemoveStatusEffect(int client, StatusEffect effect) {
    if (!IsValidClient(client)) return;
    
    int effectIndex = view_as<int>(effect) - 1;
    if (effectIndex < 0 || effectIndex >= 3) return;
    
    if (g_bStatusEffects[client][effectIndex]) {
        g_bStatusEffects[client][effectIndex] = false;
        g_fStatusStartTime[client][effectIndex] = 0.0;
        
        // 골절 치료 시 이동속도 즉시 복구
        if (effect == STATUS_FRACTURE) {
            SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", 300.0);
        }
        
        char effectName[32];
        GetStatusEffectName(effect, effectName, sizeof(effectName));
        
        PrintToChat(client, "\x04[데이즈]\x01 %s 상태가 치료되었습니다!", effectName);
        
        // 포워드 호출
        Call_StartForward(g_hOnStatusEffectRemove);
        Call_PushCell(client);
        Call_PushCell(view_as<int>(effect));
        Call_Finish();
    }
}

void GetStatusEffectName(StatusEffect effect, char[] buffer, int maxlen) {
    switch (effect) {
        case STATUS_BLEEDING: strcopy(buffer, maxlen, "출혈");
        case STATUS_FRACTURE: strcopy(buffer, maxlen, "골절");
        case STATUS_COLD: strcopy(buffer, maxlen, "감기");
        default: strcopy(buffer, maxlen, "알 수 없는 상태");
    }
}

void UpdatePlayerHUD(int client) {
    SetHudTextParams(0.02, 0.02, 1.1, 255, 255, 255, 255);
    
    int hungerPercent = RoundToNearest((g_fHunger[client] / DEFAULT_HUNGER) * 100);
    int thirstPercent = RoundToNearest((g_fThirst[client] / DEFAULT_THIRST) * 100);
    int staminaPercent = RoundToNearest((g_fStamina[client] / DEFAULT_STAMINA) * 100);
    
    if (hungerPercent > 100) hungerPercent = 100;
    if (thirstPercent > 100) thirstPercent = 100;
    if (staminaPercent > 100) staminaPercent = 100;
    
    if (hungerPercent < 0) hungerPercent = 0;
    if (thirstPercent < 0) thirstPercent = 0;
    if (staminaPercent < 0) staminaPercent = 0;
    
    // 상태 이상 텍스트 생성
    char statusText[128] = "";
    bool hasStatus = false;
    
    if (g_bStatusEffects[client][view_as<int>(STATUS_BLEEDING) - 1]) {
        StrCat(statusText, sizeof(statusText), "출혈 ");
        hasStatus = true;
    }
    if (g_bStatusEffects[client][view_as<int>(STATUS_FRACTURE) - 1]) {
        StrCat(statusText, sizeof(statusText), "골절 ");
        hasStatus = true;
    }
    if (g_bStatusEffects[client][view_as<int>(STATUS_COLD) - 1]) {
        StrCat(statusText, sizeof(statusText), "감기 ");
        hasStatus = true;
    }
    
    // HUD 텍스트 구성
    char hudText[256];
    if (hasStatus) {
        Format(hudText, sizeof(hudText), 
            "배고픔: %d%%\n목마름: %d%%\n스태미나: %d%%\n상태이상: %s",
            hungerPercent, thirstPercent, staminaPercent, statusText);
    } else {
        Format(hudText, sizeof(hudText), 
            "배고픔: %d%%\n목마름: %d%%\n스태미나: %d%%",
            hungerPercent, thirstPercent, staminaPercent);
    }
    
    ShowSyncHudText(client, g_hHudSync, hudText);
}

void ResetPlayerStatus(int client) {
    g_iKills[client] = 0;
    g_iDeaths[client] = 0;
    g_iKarma[client] = DEFAULT_KARMA;
    g_fHunger[client] = DEFAULT_HUNGER;
    g_fThirst[client] = DEFAULT_THIRST;
    g_fStamina[client] = DEFAULT_STAMINA;
    g_bIsSprinting[client] = false;
    g_bHasPosition[client] = false;
    g_fLastSprintTime[client] = 0.0;
    
    // 상태이상 완전 초기화 추가
    for (int i = 0; i < 3; i++) {
        g_bStatusEffects[client][i] = false;
        g_fStatusStartTime[client][i] = 0.0;
        g_iBackupStatusEffects[client][i] = 0;
    }
    g_fLastBleedingDamage[client] = 0.0;
    g_fWaterStartTime[client] = 0.0;
    g_bInWater[client] = false;
    g_bStatusBackupDone[client] = false;
}

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsValidAdmin(int client) {
    return (IsValidClient(client) && CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT));
}

float FloatMin(float a, float b) {
    return (a < b) ? a : b;
}

float FloatMax(float a, float b) {
    return (a > b) ? a : b;
}