#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#include "dayz/dayz_core.inc"

// 데이터베이스 변수
Database g_Database = null;
bool g_bDataLoaded[MAXPLAYERS + 1][4];
int g_iBackupHealth[MAXPLAYERS + 1];
bool g_bHealthBackupDone[MAXPLAYERS + 1];
int g_iBackupAmmo[MAXPLAYERS + 1][3];
bool g_bAmmoBackupDone[MAXPLAYERS + 1];
int g_iBackupStatusEffects[MAXPLAYERS + 1][3];
bool g_bStatusBackupDone[MAXPLAYERS + 1];

// 외부 변수 참조용 (다른 플러그인에서 가져올 값들)
extern InventorySlot g_PlayerInventory[MAXPLAYERS + 1][INVENTORY_SIZE];
extern WeaponData g_WeaponData[MAXPLAYERS + 1][5];

public Plugin myinfo = {
    name = "TF2 DayZ Mode - Database",
    author = "FinN",
    description = "DayZ Database System for Team Fortress 2",
    version = PLUGIN_VERSION,
    url = "https://steamcommunity.com/profiles/76561198041705012/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    // 네이티브 함수 등록
    CreateNative("DayZ_SavePlayerData", Native_SavePlayerData);
    CreateNative("DayZ_LoadPlayerData", Native_LoadPlayerData);
    CreateNative("DayZ_SavePlayerInventory", Native_SavePlayerInventory);
    CreateNative("DayZ_LoadPlayerInventory", Native_LoadPlayerInventory);
    CreateNative("DayZ_SavePlayerWeapons", Native_SavePlayerWeapons);
    CreateNative("DayZ_LoadPlayerWeapons", Native_LoadPlayerWeapons);
    CreateNative("DayZ_IsPlayerDataLoaded", Native_IsPlayerDataLoaded);
    
    RegPluginLibrary("dayz_database");
    return APLRes_Success;
}

public void OnPluginStart() {
    // 명령어 등록
    RegConsoleCmd("sm_save", Command_SaveMyData, "내 데이터 저장");
    RegAdminCmd("sm_dayz_save", Command_SaveAllData, ADMFLAG_ROOT, "모든 데이터 수동 저장");
    
    // 데이터베이스 연결
    Database.Connect(SQL_ConnectCallback, "dayz_mode");
    
    // 타이머 생성
    CreateTimer(30.0, Timer_SaveAllData, _, TIMER_REPEAT);
    CreateTimer(10.0, Timer_AutoSave, _, TIMER_REPEAT);
    
    // 클라이언트 초기화
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i)) {
            OnClientPutInServer(i);
        }
    }
}

public void OnClientPutInServer(int client) {
    if (!IsValidClient(client)) return;
    
    // 데이터 로드 상태 초기화
    for (int i = 0; i < 4; i++) {
        g_bDataLoaded[client][i] = false;
    }
    
    // 백업 시스템 초기화
    g_iBackupHealth[client] = MAX_HEALTH;
    g_bHealthBackupDone[client] = false;
    g_bAmmoBackupDone[client] = false;
    g_bStatusBackupDone[client] = false;
    
    for (int i = 0; i < 3; i++) {
        g_iBackupAmmo[client][i] = 0;
        g_iBackupStatusEffects[client][i] = 0;
    }
    
    // Steam ID 가져오기 및 데이터 로드
    char steam_id[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id))) {
        PrintToChat(client, "\x04[데이즈]\x01 Steam ID를 가져오는데 실패했습니다.");
        return;
    }
    
    // 플레이어 기본 정보 로드
    char query[256];
    Format(query, sizeof(query), "SELECT * FROM player_stats WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_LoadPlayerCallback, query, GetClientUserId(client));
    
    // 인벤토리 로드
    Format(query, sizeof(query), "SELECT * FROM player_inventory WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_LoadInventoryCallback, query, GetClientUserId(client));
    
    // 무기 정보 로드
    Format(query, sizeof(query), "SELECT * FROM player_weapons WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_LoadWeaponsAndBackupCallback, query, GetClientUserId(client));
    
    // 상태 이상 로드
    Format(query, sizeof(query), "SELECT * FROM player_status_effects WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_LoadStatusEffectsCallback, query, GetClientUserId(client));
    
    PrintToChat(client, "\x04[데이즈]\x01 데이터를 불러오는 중입니다...");
}

public void OnClientDisconnect(int client) {
    if (IsValidClient(client)) {
        if (IsPlayerAlive(client)) {
            // 현재 위치와 체력 백업
            float pos[3], ang[3];
            GetClientAbsOrigin(client, pos);
            GetClientEyeAngles(client, ang);
            
            g_iBackupHealth[client] = GetClientHealth(client);
            g_bHealthBackupDone[client] = true;
        }
        
        for (int i = 0; i < 4; i++) {
            g_bDataLoaded[client][i] = false;
        }
        
        SavePlayerData(client);
        SavePlayerInventory(client);
        SavePlayerWeapons(client);
    }
}

public void OnMapEnd() {
    // 모든 플레이어 데이터 저장
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i)) {
            SaveAllPlayerData(i);
        }
    }
    
    PrintToServer("[데이즈] 맵 종료: 모든 플레이어 데이터 저장 완료");
}

// 네이티브 함수 구현
public int Native_SavePlayerData(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    SavePlayerData(client);
    return 0;
}

public int Native_LoadPlayerData(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    LoadPlayerData(client);
    return 0;
}

public int Native_SavePlayerInventory(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    SavePlayerInventory(client);
    return 0;
}

public int Native_LoadPlayerInventory(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    LoadPlayerInventory(client);
    return 0;
}

public int Native_SavePlayerWeapons(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    SavePlayerWeapons(client);
    return 0;
}

public int Native_LoadPlayerWeapons(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    LoadPlayerWeapons(client);
    return 0;
}

public int Native_IsPlayerDataLoaded(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int dataType = GetNativeCell(2);
    
    if (dataType < 0 || dataType >= 4) return false;
    return g_bDataLoaded[client][dataType];
}

// 명령어 핸들러
public Action Command_SaveMyData(int client, int args) {
    if (!IsValidClient(client)) {
        return Plugin_Handled;
    }
    
    if (IsPlayerAlive(client)) {
        float pos[3], ang[3];
        GetClientAbsOrigin(client, pos);
        GetClientEyeAngles(client, ang);
        
        g_iBackupHealth[client] = GetClientHealth(client);
        g_bHealthBackupDone[client] = true;
    }
    
    SavePlayerData(client);
    SavePlayerInventory(client);
    SavePlayerWeapons(client);
    
    PrintToChat(client, "\x04[데이즈]\x01 당신의 데이터가 저장되었습니다.");
    
    return Plugin_Handled;
}

public Action Command_SaveAllData(int client, int args) {
    if (!IsValidAdmin(client)) {
        PrintToChat(client, "\x04[데이즈]\x01 이 명령어는 관리자만 사용할 수 있습니다.");
        return Plugin_Handled;
    }
    
    int savedCount = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i)) {
            SavePlayerData(i);
            SavePlayerInventory(i);
            SavePlayerWeapons(i);
            savedCount++;
            
            PrintToChat(i, "\x04[데이즈]\x01 당신의 데이터가 저장되었습니다.");
        }
    }
    
    PrintToChat(client, "\x04[데이즈]\x01 총 %d명의 플레이어 데이터가 저장되었습니다.", savedCount);
    
    return Plugin_Handled;
}

// 타이머 함수
public Action Timer_SaveAllData(Handle timer) {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsValidClient(client)) {
            SavePlayerData(client);
        }
    }
    
    return Plugin_Continue;
}

public Action Timer_AutoSave(Handle timer) {
    if (!DayZ_IsEnabled()) return Plugin_Continue;
    
    for (int client = 1; client <= MaxClients; client++) {
        if (IsValidClient(client)) {
            if (IsPlayerAlive(client)) {
                float pos[3], ang[3];
                GetClientAbsOrigin(client, pos);
                GetClientEyeAngles(client, ang);
                
                g_iBackupHealth[client] = GetClientHealth(client);
                g_bHealthBackupDone[client] = true;
            }
            
            SaveAllPlayerData(client);
        }
    }
    
    return Plugin_Continue;
}

// 데이터베이스 함수
public void SQL_ConnectCallback(Database db, const char[] error, any data) {
    if (db == null) {
        SetFailState("데이터베이스 연결 실패: %s", error);
        return;
    }
    
    g_Database = db;
    g_Database.SetCharset("utf8mb4");
    
    char query[1024];
    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS player_stats ( \
        steam_id VARCHAR(32) PRIMARY KEY, \
        kills INT DEFAULT 0, \
        deaths INT DEFAULT 0, \
        karma INT DEFAULT %d, \
        hunger FLOAT DEFAULT %f, \
        thirst FLOAT DEFAULT %f, \
        stamina FLOAT DEFAULT %f, \
        pos_x FLOAT DEFAULT 0.0, \
        pos_y FLOAT DEFAULT 0.0, \
        pos_z FLOAT DEFAULT 0.0, \
        ang_x FLOAT DEFAULT 0.0, \
        ang_y FLOAT DEFAULT 0.0, \
        ang_z FLOAT DEFAULT 0.0, \
        has_position BOOLEAN DEFAULT FALSE, \
        health INT DEFAULT %d \
        )", DEFAULT_KARMA, DEFAULT_HUNGER, DEFAULT_THIRST, DEFAULT_STAMINA, MAX_HEALTH);
    
    g_Database.Query(SQL_GenericCallback, query);
    
    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS player_inventory ( \
        steam_id VARCHAR(32), \
        slot INT, \
        item_id VARCHAR(32), \
        amount INT DEFAULT 1, \
        item_type INT DEFAULT 0, \
        weapon_data VARCHAR(64), \
        PRIMARY KEY (steam_id, slot) \
        )");
    
    g_Database.Query(SQL_GenericCallback, query);

    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS player_weapons ( \
        steam_id VARCHAR(32), \
        slot INT, \
        weapon_id VARCHAR(32), \
        weapon_type INT DEFAULT 0, \
        current_ammo INT DEFAULT 0, \
        max_ammo INT DEFAULT 25, \
        damage INT DEFAULT 40, \
        slot_type INT DEFAULT 0, \
        PRIMARY KEY (steam_id, slot) \
        )");

    g_Database.Query(SQL_GenericCallback, query);
    
    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS player_status_effects ( \
        steam_id VARCHAR(32) PRIMARY KEY, \
        bleeding BOOLEAN DEFAULT FALSE, \
        fracture BOOLEAN DEFAULT FALSE, \
        cold BOOLEAN DEFAULT FALSE, \
        bleeding_start FLOAT DEFAULT 0.0, \
        fracture_start FLOAT DEFAULT 0.0, \
        cold_start FLOAT DEFAULT 0.0 \
        )");

    g_Database.Query(SQL_GenericCallback, query);
}

public void SQL_GenericCallback(Database db, DBResultSet results, const char[] error, any data) {
    if (results == null) {
        LogError("Query failed: %s", error);
    }
}

public void SQL_LoadPlayerCallback(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (!IsValidClient(client)) return;
    
    if (results == null) {
        PrintToChat(client, "\x04[데이즈]\x01 데이터 로드 중 오류가 발생했습니다.");
        LogError("Query failed: %s", error);
        return;
    }
    
    if (results.FetchRow()) {
        // 플레이어 스탯 로드
        int kills = results.FetchInt(1);
        int deaths = results.FetchInt(2);
        int karma = results.FetchInt(3);
        float hunger = results.FetchFloat(4);
        float thirst = results.FetchFloat(5);
        float stamina = results.FetchFloat(6);
        
        float pos[3], ang[3];
        pos[0] = results.FetchFloat(7);
        pos[1] = results.FetchFloat(8);
        pos[2] = results.FetchFloat(9);
        ang[0] = results.FetchFloat(10);
        ang[1] = results.FetchFloat(11);
        ang[2] = results.FetchFloat(12);
        
        bool hasPosition = results.FetchInt(13) == 1;
        
        // 체력 데이터 백업
        int dbHealth = results.FetchInt(14);
        
        // 체력 값 검증
        if (dbHealth <= 0) {
            dbHealth = MAX_HEALTH;
        }
        if (dbHealth > MAX_HEALTH + 200) {
            dbHealth = MAX_HEALTH + 200;
        }
        
        // 백업에 저장
        g_iBackupHealth[client] = dbHealth;
        g_bHealthBackupDone[client] = true;
        
        // 다른 플러그인의 데이터 설정
        DayZ_SetPlayerKarma(client, karma);
        DayZ_SetPlayerHunger(client, hunger);
        DayZ_SetPlayerThirst(client, thirst);
        DayZ_SetPlayerStamina(client, stamina);
        
    } else {
        // 새 플레이어
        g_iBackupHealth[client] = MAX_HEALTH;
        g_bHealthBackupDone[client] = false;
    }
    
    g_bDataLoaded[client][0] = true;
    CheckAndTeleportPlayer(client);
}

public void SQL_LoadInventoryCallback(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (!IsValidClient(client)) return;
    
    if (results == null) {
        LogError("Query failed: %s", error);
        return;
    }
    
    // 인벤토리 초기화는 인벤토리 플러그인에서 처리
    
    while (results.FetchRow()) {
        int slot = results.FetchInt(1);
        if (slot >= 0 && slot < INVENTORY_SIZE) {
            char itemId[32];
            results.FetchString(2, itemId, sizeof(itemId));
            
            int amount = results.FetchInt(3);
            int type = results.FetchInt(4);
            
            // 무기 데이터 로드
            char weaponData[128];
            results.FetchString(5, weaponData, sizeof(weaponData));
            
            // 인벤토리 플러그인 네이티브 사용하여 아이템 추가
            DayZ_GivePlayerItem(client, itemId, amount, type);
        }
    }
    
    g_bDataLoaded[client][1] = true;
    CheckAndTeleportPlayer(client);
}

public void SQL_LoadWeaponsAndBackupCallback(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (!IsValidClient(client)) return;
    
    if (results == null) {
        LogError("Query failed: %s", error);
        return;
    }
    
    // 무기 데이터 초기화는 무기 플러그인에서 처리
    
    while (results.FetchRow()) {
        int slot = results.FetchInt(1);
        if (slot >= 0 && slot < 5) {
            char weaponId[32];
            results.FetchString(2, weaponId, sizeof(weaponId));
            
            int dbCurrentAmmo = results.FetchInt(4);
            int dbMaxAmmo = results.FetchInt(5);
            
            // 근접무기가 아닌 경우만 탄약 처리
            if (slot < 3) {
                int validatedMaxAmmo = dbMaxAmmo;
                if (validatedMaxAmmo <= 0 || validatedMaxAmmo > 254) {
                    validatedMaxAmmo = 25;
                }
                
                int validatedCurrentAmmo = dbCurrentAmmo;
                if (validatedCurrentAmmo < 0) {
                    validatedCurrentAmmo = 0;
                }
                if (validatedCurrentAmmo > validatedMaxAmmo) {
                    validatedCurrentAmmo = validatedMaxAmmo;
                }
                if (validatedCurrentAmmo > 254) {
                    validatedCurrentAmmo = 254;
                }
                
                // 백업 저장
                g_iBackupAmmo[client][slot] = validatedCurrentAmmo;
                
                // 무기 시스템에 무기 장착 요청
                DayZ_EquipWeapon(client, weaponId);
                DayZ_SetWeaponAmmo(client, slot, validatedCurrentAmmo);
            }
        }
    }
    
    g_bAmmoBackupDone[client] = true;
    g_bDataLoaded[client][2] = true;
    CheckAndTeleportPlayer(client);
}

public void SQL_LoadStatusEffectsCallback(Database db, DBResultSet results, const char[] error, any data) {
    int client = GetClientOfUserId(data);
    if (!IsValidClient(client)) return;
    
    if (results == null) {
        LogError("Query failed: %s", error);
        return;
    }
    
    if (results.FetchRow()) {
        // 백업에만 저장
        g_iBackupStatusEffects[client][view_as<int>(STATUS_BLEEDING) - 1] = results.FetchInt(1);
        g_iBackupStatusEffects[client][view_as<int>(STATUS_FRACTURE) - 1] = results.FetchInt(2);
        g_iBackupStatusEffects[client][view_as<int>(STATUS_COLD) - 1] = results.FetchInt(3);
        
        g_bStatusBackupDone[client] = true;
    } else {
        // 데이터가 없으면 초기화
        for (int i = 0; i < 3; i++) {
            g_iBackupStatusEffects[client][i] = 0;
        }
        g_bStatusBackupDone[client] = false;
    }
    
    g_bDataLoaded[client][3] = true;
    CheckAndTeleportPlayer(client);
}

void CheckAndTeleportPlayer(int client) {
    if (!IsValidClient(client)) return;
    
    // 4개 데이터 모두 로드 완료 확인
    if (g_bDataLoaded[client][0] && g_bDataLoaded[client][1] && 
        g_bDataLoaded[client][2] && g_bDataLoaded[client][3]) {
        
        // 백업된 탄약값 복원
        if (g_bAmmoBackupDone[client]) {
            for (int slot = 0; slot < 3; slot++) {
                if (DayZ_HasWeapon(client, slot) && g_iBackupAmmo[client][slot] >= 0) {
                    DayZ_SetWeaponAmmo(client, slot, g_iBackupAmmo[client][slot]);
                }
            }
        }
        
        // 백업된 체력 복원
        if (g_bHealthBackupDone[client] && IsPlayerAlive(client)) {
            SetEntityHealth(client, g_iBackupHealth[client]);
        }
        
        PrintToChat(client, "\x04[데이즈]\x01 데이터 로드가 완료되었습니다!");
        
        // 포워드 호출
        Call_StartForward(DayZ_OnPlayerDataLoaded);
        Call_PushCell(client);
        Call_Finish();
    }
}

void SavePlayerData(int client) {
    if (!IsValidClient(client) || g_Database == null) return;
    
    char steam_id[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id))) return;

    int currentHealth = IsPlayerAlive(client) ? GetClientHealth(client) : g_iBackupHealth[client];
    
    float pos[3] = {0.0, 0.0, 0.0};
    float ang[3] = {0.0, 0.0, 0.0};
    bool hasPosition = false;
    
    if (IsPlayerAlive(client)) {
        GetClientAbsOrigin(client, pos);
        GetClientEyeAngles(client, ang);
        hasPosition = true;
    }

    char query[512];
    Format(query, sizeof(query),
        "REPLACE INTO player_stats \
        (steam_id, kills, deaths, karma, hunger, thirst, stamina, pos_x, pos_y, pos_z, ang_x, ang_y, ang_z, has_position, health) \
        VALUES ('%s', %d, %d, %d, %f, %f, %f, %f, %f, %f, %f, %f, %f, %d, %d)",
        steam_id,
        0, 0, DayZ_GetPlayerKarma(client),
        DayZ_GetPlayerHunger(client), DayZ_GetPlayerThirst(client), DayZ_GetPlayerStamina(client),
        pos[0], pos[1], pos[2],
        ang[0], ang[1], ang[2],
        hasPosition ? 1 : 0,
        currentHealth);
    
    g_Database.Query(SQL_GenericCallback, query);
}

void SavePlayerInventory(int client) {
    if (!IsValidClient(client) || g_Database == null) return;
    
    char steam_id[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id))) return;
    
    char query[512];
    Format(query, sizeof(query), "DELETE FROM player_inventory WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_GenericCallback, query);
    
    // 인벤토리 저장은 인벤토리 플러그인에서 처리
}

void SavePlayerWeapons(int client) {
    if (!IsValidClient(client) || g_Database == null) return;
    
    char steam_id[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id))) return;
    
    char query[512];
    Format(query, sizeof(query), "DELETE FROM player_weapons WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_GenericCallback, query);
    
    for (int slot = 0; slot < 5; slot++) {
        if (DayZ_HasWeapon(client, slot)) {
            char weaponId[32];
            DayZ_GetWeaponId(client, slot, weaponId, sizeof(weaponId));
            
            int currentAmmo = (slot < 3) ? DayZ_GetWeaponAmmo(client, slot) : 0;
            
            // 탄약 검증
            if (currentAmmo < 0) {
                currentAmmo = 0;
            }
            if (currentAmmo > 254) {
                currentAmmo = 254;
            }
            
            Format(query, sizeof(query),
                "INSERT INTO player_weapons \
                (steam_id, slot, weapon_id, weapon_type, current_ammo, max_ammo, damage) \
                VALUES ('%s', %d, '%s', %d, %d, %d, %d)",
                steam_id, slot, weaponId,
                0, // weapon_type
                currentAmmo,
                25, // max_ammo
                40); // damage
            
            g_Database.Query(SQL_GenericCallback, query);
        }
    }
}

void SaveAllPlayerData(int client) {
    if (!IsValidClient(client)) return;
    
    if (IsPlayerAlive(client)) {
        g_iBackupHealth[client] = GetClientHealth(client);
        g_bHealthBackupDone[client] = true;
    }
    
    SavePlayerData(client);
    SavePlayerInventory(client);
    SavePlayerWeapons(client);
}

void LoadPlayerData(int client) {
    if (!IsValidClient(client) || g_Database == null) return;
    
    char steam_id[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id))) return;
    
    char query[256];
    Format(query, sizeof(query), "SELECT * FROM player_stats WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_LoadPlayerCallback, query, GetClientUserId(client));
}

void LoadPlayerInventory(int client) {
    if (!IsValidClient(client) || g_Database == null) return;
    
    char steam_id[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id))) return;
    
    char query[256];
    Format(query, sizeof(query), "SELECT * FROM player_inventory WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_LoadInventoryCallback, query, GetClientUserId(client));
}

void LoadPlayerWeapons(int client) {
    if (!IsValidClient(client) || g_Database == null) return;
    
    char steam_id[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steam_id, sizeof(steam_id))) return;
    
    char query[256];
    Format(query, sizeof(query), "SELECT * FROM player_weapons WHERE steam_id = '%s'", steam_id);
    g_Database.Query(SQL_LoadWeaponsAndBackupCallback, query, GetClientUserId(client));
}

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsValidAdmin(int client) {
    return (IsValidClient(client) && CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT));
}

// 포워드 핸들
Handle DayZ_OnPlayerDataLoaded;

public void OnAllPluginsLoaded() {
    DayZ_OnPlayerDataLoaded = FindConVar("DayZ_OnPlayerDataLoaded");
}