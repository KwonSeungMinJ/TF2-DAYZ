#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <tf2attributes>
#include <tf2items>

#pragma semicolon 1
#pragma newdecls required

#include "dayz/dayz_core.inc"

// 무기 시스템 변수
WeaponData g_WeaponData[MAXPLAYERS + 1][5];
int g_iBackupAmmo[MAXPLAYERS + 1][3];
bool g_bAmmoBackupDone[MAXPLAYERS + 1];
float g_fReloadDelay[MAXPLAYERS + 1][3];
Handle g_hReloadHudSync = null;
bool g_bReloading[MAXPLAYERS + 1][3];
float g_fReloadStartTime[MAXPLAYERS + 1][3];
int g_iLastActiveWeaponSlot[MAXPLAYERS + 1] = {-1, ...};

KeyValues g_kvItems = null;

public Plugin myinfo = {
    name = "TF2 DayZ Mode - Weapons",
    author = "FinN",
    description = "DayZ Weapon System for Team Fortress 2",
    version = PLUGIN_VERSION,
    url = "https://steamcommunity.com/profiles/76561198041705012/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    // 네이티브 함수 등록
    CreateNative("DayZ_HasWeapon", Native_HasWeapon);
    CreateNative("DayZ_GetWeaponId", Native_GetWeaponId);
    CreateNative("DayZ_EquipWeapon", Native_EquipWeapon);
    CreateNative("DayZ_RemoveWeapon", Native_RemoveWeapon);
    CreateNative("DayZ_GetWeaponAmmo", Native_GetWeaponAmmo);
    CreateNative("DayZ_SetWeaponAmmo", Native_SetWeaponAmmo);
    
    RegPluginLibrary("dayz_weapons");
    return APLRes_Success;
}

public void OnPluginStart() {
    // 이벤트 훅
    HookEvent("post_inventory_application", Event_PostInventoryApplication);
    HookEvent("player_shoot", Event_PlayerShoot);
    
    // TF2 훅
    AddNormalSoundHook(OnNormalSoundPlayed);
    
    // 리로드 HUD 초기화
    g_hReloadHudSync = CreateHudSynchronizer();
    
    // 타이머 생성
    CreateTimer(1.0, Timer_UpdateAmmo, _, TIMER_REPEAT);
    CreateTimer(0.1, Timer_UpdateReloadHUD, _, TIMER_REPEAT);
    
    // 설정 파일 로드
    LoadItemsConfig();
    
    // 클라이언트 초기화
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i)) {
            OnClientPutInServer(i);
        }
    }
    
    // 사운드 프리캐시
    PrecacheSound(EMPTY_WEAPON_SOUND);
}

public void OnMapStart() {
    LoadItemsConfig();
    PrecacheSound(EMPTY_WEAPON_SOUND);
}

public void OnClientPutInServer(int client) {
    if (!IsValidClient(client)) return;
    
    g_iLastActiveWeaponSlot[client] = -1;
    g_bAmmoBackupDone[client] = false;
    
    // 무기 데이터 초기화
    for (int i = 0; i < 5; i++) {
        strcopy(g_WeaponData[client][i].weaponId, 32, "");
        g_WeaponData[client][i].type = WEAPON_TYPE_NONE;
        g_WeaponData[client][i].currentAmmo = 0;
        g_WeaponData[client][i].maxAmmo = 0;
        g_WeaponData[client][i].damage = 0;
        g_WeaponData[client][i].slotType = 0;
        
        if (i < 3) {
            g_iBackupAmmo[client][i] = 0;
            g_bReloading[client][i] = false;
            g_fReloadDelay[client][i] = 0.0;
            g_fReloadStartTime[client][i] = 0.0;
        }
    }
    
    // 무기 제거 및 주먹 지급
    StripWeapons(client);
    CreateTimer(0.5, Timer_GiveFists, GetClientUserId(client));
}

public void OnClientDisconnect(int client) {
    if (IsValidClient(client)) {
        // 현재 들고 있는 무기의 탄약 정보 업데이트
        for (int slot = 0; slot < 3; slot++) {
            int weapon = GetPlayerWeaponSlot(client, slot);
            if (weapon != -1 && IsValidEntity(weapon)) {
                if (HasEntProp(weapon, Prop_Send, "m_iClip1")) {
                    g_WeaponData[client][slot].currentAmmo = GetEntProp(weapon, Prop_Send, "m_iClip1");
                }
            }
        }
        
        // 현재 체력을 백업에 저장
        if (IsPlayerAlive(client)) {
            g_iBackupAmmo[client][0] = g_WeaponData[client][0].currentAmmo;
            g_iBackupAmmo[client][1] = g_WeaponData[client][1].currentAmmo;
            g_iBackupAmmo[client][2] = g_WeaponData[client][2].currentAmmo;
            g_bAmmoBackupDone[client] = true;
        }
    }
}

// 네이티브 함수 구현
public int Native_HasWeapon(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int slot = GetNativeCell(2);
    
    if (slot < 0 || slot >= 5) return false;
    return strlen(g_WeaponData[client][slot].weaponId) > 0;
}

public int Native_GetWeaponId(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int slot = GetNativeCell(2);
    int maxlength = GetNativeCell(4);
    
    if (slot < 0 || slot >= 5) {
        SetNativeString(3, "", maxlength);
        return 0;
    }
    
    SetNativeString(3, g_WeaponData[client][slot].weaponId, maxlength);
    return strlen(g_WeaponData[client][slot].weaponId);
}

public int Native_EquipWeapon(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    char weaponId[32];
    GetNativeString(2, weaponId, sizeof(weaponId));
    
    return EquipWeapon(client, weaponId);
}

public int Native_RemoveWeapon(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int slot = GetNativeCell(2);
    
    if (slot < 0 || slot >= 5) return false;
    
    RemoveWeaponFromSlot(client, slot);
    return true;
}

public int Native_GetWeaponAmmo(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int slot = GetNativeCell(2);
    
    if (slot < 0 || slot >= 3) return 0;
    return g_WeaponData[client][slot].currentAmmo;
}

public int Native_SetWeaponAmmo(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int slot = GetNativeCell(2);
    int ammo = GetNativeCell(3);
    
    if (slot < 0 || slot >= 3) return false;
    
    g_WeaponData[client][slot].currentAmmo = ammo;
    
    int weapon = GetPlayerWeaponSlot(client, slot);
    if (weapon != -1 && IsValidEntity(weapon)) {
        SetWeaponAmmo(weapon, ammo);
    }
    
    return true;
}

// 이벤트 핸들러
public void Event_PostInventoryApplication(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    for (int slot = 0; slot < 3; slot++) {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon != -1) {
            char className[64];
            GetEntityClassname(weapon, className, sizeof(className));
            
            if (StrEqual(className, "tf_weapon_sniperrifle")) {
                if (HasEntProp(weapon, Prop_Send, "m_flChargeLevel")) {
                    SetEntPropFloat(weapon, Prop_Send, "m_flChargeLevel", 0.0);
                }
            }
        }
    }
}

public void Event_PlayerShoot(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (activeWeapon != -1) {
        int slot = GetSlotFromWeapon(client, activeWeapon);
        if (slot != -1) {
            if (HasEntProp(activeWeapon, Prop_Send, "m_iClip1")) {
                int currentAmmo = GetEntProp(activeWeapon, Prop_Send, "m_iClip1");
                
                // 탄약이 변경되었을 때만 저장
                if (g_WeaponData[client][slot].currentAmmo != currentAmmo) {
                    g_WeaponData[client][slot].currentAmmo = currentAmmo;
                }
            }
        }
    }
}

public Action OnNormalSoundPlayed(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], 
                                 int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, 
                                 char soundEntry[PLATFORM_MAX_PATH], int &seed) {
    
    if (entity > 0 && entity <= MaxClients && IsValidClient(entity)) {
        // 빈 무기 사운드 처리
        if (StrContains(sample, "empty") != -1) {
            // 기본 빈 무기 사운드로 대체
            strcopy(sample, sizeof(sample), EMPTY_WEAPON_SOUND);
            return Plugin_Changed;
        }
    }
    
    return Plugin_Continue;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool& result) {
    if (!IsValidClient(client) || weapon == -1) return Plugin_Continue;
    
    int slot = GetSlotFromWeapon(client, weapon);
    if (slot != -1) {
        if (HasEntProp(weapon, Prop_Send, "m_iClip1")) {
            int currentAmmo = GetEntProp(weapon, Prop_Send, "m_iClip1");
            
            // 탄약이 변경되었을 때만 저장
            if (g_WeaponData[client][slot].currentAmmo != currentAmmo) {
                g_WeaponData[client][slot].currentAmmo = currentAmmo;
            }
            
            // 근접무기가 아닌 경우에만 탄약 검사
            if (g_WeaponData[client][slot].type != WEAPON_TYPE_MELEE && currentAmmo == 0) {
                EmitSoundToClient(client, EMPTY_WEAPON_SOUND);
            }
        }
    }
    
    return Plugin_Continue;
}

// 타이머 함수
public Action Timer_UpdateAmmo(Handle timer) {
    if (!DayZ_IsEnabled()) return Plugin_Continue;
    
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsValidClient(client) || !IsPlayerAlive(client)) continue;
        
        // 모든 무기 슬롯의 탄약 상태 동기화
        for (int slot = 0; slot < 3; slot++) {
            if (strlen(g_WeaponData[client][slot].weaponId) > 0) {
                int weapon = GetPlayerWeaponSlot(client, slot);
                if (weapon != -1 && IsValidEntity(weapon)) {
                    if (HasEntProp(weapon, Prop_Send, "m_iClip1")) {
                        int currentAmmo = GetEntProp(weapon, Prop_Send, "m_iClip1");
                        
                        // 실제 변경이 있을 때만 업데이트
                        if (g_WeaponData[client][slot].currentAmmo != currentAmmo) {
                            g_WeaponData[client][slot].currentAmmo = currentAmmo;
                        }
                    }
                }
            }
        }
    }
    
    return Plugin_Continue;
}

public Action Timer_UpdateReloadHUD(Handle timer) {
    if (!DayZ_IsEnabled()) return Plugin_Continue;
    
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsValidClient(client) || !IsPlayerAlive(client)) continue;
        
        UpdateReloadHUD(client);
    }
    
    return Plugin_Continue;
}

public Action Timer_GiveFists(Handle timer, any data) {
    int client = GetClientOfUserId(data);
    if (!IsValidClient(client) || !IsPlayerAlive(client)) {
        return Plugin_Stop;
    }
    
    GivePlayerFists(client);
    return Plugin_Stop;
}

// 무기 관련 주요 함수
bool EquipWeapon(int client, const char[] weaponId) {
    if (!g_kvItems.JumpToKey(weaponId)) {
        PrintToChat(client, "\x04[데이즈]\x01 무기 정보를 찾을 수 없습니다.");
        return false;
    }
    
    char className[64], itemName[64];
    g_kvItems.GetString("classname", className, sizeof(className));
    g_kvItems.GetString("name", itemName, sizeof(itemName));
    int slot = g_kvItems.GetNum("slot", 0);
    int damage = g_kvItems.GetNum("damage", 40);
    int maxAmmo = g_kvItems.GetNum("max_ammo", 25);
    int itemIndex = g_kvItems.GetNum("item_index", -1);
    WeaponType type = view_as<WeaponType>(g_kvItems.GetNum("weapon_type", 1));
    
    // 기존 무기 제거
    TF2_RemoveWeaponSlot(client, slot);
    
    // TF2Items를 사용한 무기 생성
    Handle hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
    
    if (hWeapon == null) {
        PrintToChat(client, "\x04[데이즈]\x01 무기 생성에 실패했습니다.");
        g_kvItems.Rewind();
        return false;
    }
    
    // 무기 설정
    TF2Items_SetClassname(hWeapon, className);
    
    if (itemIndex != -1) {
        TF2Items_SetItemIndex(hWeapon, itemIndex);
    } else {
        TF2Items_SetItemIndex(hWeapon, GetDefaultItemIndex(className));
    }
    
    TF2Items_SetLevel(hWeapon, 1);
    TF2Items_SetQuality(hWeapon, 0);
    
    // 기본 속성 설정
    TF2Items_SetNumAttributes(hWeapon, 3);
    TF2Items_SetAttribute(hWeapon, 0, 77, 0.0);
    TF2Items_SetAttribute(hWeapon, 1, 78, 0.0);
    TF2Items_SetAttribute(hWeapon, 2, 303, -1.0);
    
    int weapon = TF2Items_GiveNamedItem(client, hWeapon);
    delete hWeapon;
    
    if (weapon == -1) {
        PrintToChat(client, "\x04[데이즈]\x01 무기를 장착할 수 없습니다.");
        g_kvItems.Rewind();
        return false;
    }
    
    // 무기 장착
    EquipPlayerWeapon(client, weapon);
    
    // 초기 탄약 설정
    SetWeaponAmmo(weapon, 0);
    
    // 무기 속성 적용
    ApplyWeaponAttributes(client, weapon, weaponId);
    
    // 무기를 활성 무기로 설정
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
    
    // 무기 데이터 저장
    strcopy(g_WeaponData[client][slot].weaponId, 32, weaponId);
    g_WeaponData[client][slot].type = type;
    g_WeaponData[client][slot].currentAmmo = 0;
    g_WeaponData[client][slot].maxAmmo = maxAmmo;
    g_WeaponData[client][slot].damage = damage;
    g_WeaponData[client][slot].slotType = slot;
    
    PrintToChat(client, "\x04[데이즈]\x01 %s을(를) 장착했습니다. (탄약: 0/%d)", itemName, maxAmmo);
    
    g_kvItems.Rewind();
    
    // 포워드 호출
    Call_StartForward(DayZ_OnWeaponEquip);
    Call_PushCell(client);
    Call_PushCell(slot);
    Call_PushString(weaponId);
    Call_Finish();
    
    return true;
}

void RemoveWeaponFromSlot(int client, int slot) {
    if (!IsValidClient(client) || slot < 0 || slot >= 5) return;
    
    if (strlen(g_WeaponData[client][slot].weaponId) > 0) {
        // 무기 제거
        TF2_RemoveWeaponSlot(client, slot);
        
        // 무기 데이터 초기화
        g_WeaponData[client][slot].weaponId[0] = '\0';
        g_WeaponData[client][slot].type = WEAPON_TYPE_NONE;
        g_WeaponData[client][slot].currentAmmo = 0;
        g_WeaponData[client][slot].maxAmmo = 0;
        g_WeaponData[client][slot].damage = 0;
        
        // 근접무기 슬롯이면 주먹 지급
        if (slot == 2) {
            CreateTimer(0.1, Timer_GiveFists, GetClientUserId(client));
        }
    }
}

void ApplyWeaponAttributes(int client, int weapon, const char[] weaponId) {
    if (!IsValidEntity(weapon)) return;
    
    WeaponAttributes attrs;
    if (!LoadWeaponAttributes(weaponId, attrs)) {
        return; // 속성이 없으면 기본 무기
    }
    
    // 1. 데미지 배율 적용 (속성 2)
    if (attrs.damageMultiplier != 1.0) {
        TF2Attrib_SetByDefIndex(weapon, 2, attrs.damageMultiplier);
    }
    
    // 2. 발사속도 적용 (속성 6)
    if (attrs.fireRateMultiplier != 1.0) {
        TF2Attrib_SetByDefIndex(weapon, 6, attrs.fireRateMultiplier);
    }
    
    // 3. 저격총 충전속도 적용 (속성 304)
    char className[64];
    GetEntityClassname(weapon, className, sizeof(className));
    if (StrContains(className, "tf_weapon_sniperrifle") != -1) {
        if (attrs.chargeRateMultiplier != 1.0) {
            TF2Attrib_SetByDefIndex(weapon, 304, attrs.chargeRateMultiplier);
        }
        
        if (attrs.noScope) {
            TF2Attrib_SetByDefIndex(weapon, 42, 1.0); // 스코프 제거
            TF2Attrib_SetByDefIndex(weapon, 305, 1.0); // 충전 제거
        }
    }
    
    // 4. 정확도 적용 (속성 106)
    if (attrs.accuracyMultiplier != 1.0) {
        TF2Attrib_SetByDefIndex(weapon, 106, 2.0 - attrs.accuracyMultiplier);
    }
    
    // 5. 재장전 속도 적용 (속성 97)
    if (attrs.reloadSpeedMultiplier != 1.0) {
        TF2Attrib_SetByDefIndex(weapon, 97, attrs.reloadSpeedMultiplier);
    }
    
    // 6. 최대 탄약 보너스 (속성 78)
    if (attrs.ammoBonus != 0) {
        TF2Attrib_SetByDefIndex(weapon, 78, float(attrs.ammoBonus));
    }
    
    // 7. 크리티컬 제거 (속성 236)
    if (attrs.noCrits) {
        TF2Attrib_SetByDefIndex(weapon, 236, 1.0);
    }
    
    // 8. 이동속도 적용 (속성 54)
    if (attrs.movementSpeedMultiplier != 1.0) {
        TF2Attrib_SetByDefIndex(weapon, 54, attrs.movementSpeedMultiplier);
    }
    
    // 9. 플레이어 체력 보너스 적용 (속성 77)
    if (attrs.healthBonus != 0) {
        TF2Attrib_SetByDefIndex(weapon, 77, float(attrs.healthBonus));
        
        // 즉시 체력 적용
        int currentHealth = GetClientHealth(client);
        int newMaxHealth = MAX_HEALTH + attrs.healthBonus;
        if (currentHealth < newMaxHealth) {
            SetEntityHealth(client, newMaxHealth);
        }
    }
}

bool LoadWeaponAttributes(const char[] weaponId, WeaponAttributes attrs) {
    if (!g_kvItems.JumpToKey(weaponId)) {
        return false;
    }
    
    // 기본값 설정
    attrs.damageMultiplier = g_kvItems.GetFloat("damage_multiplier", 1.0);
    attrs.fireRateMultiplier = g_kvItems.GetFloat("fire_rate_multiplier", 1.0);
    attrs.chargeRateMultiplier = g_kvItems.GetFloat("charge_rate_multiplier", 1.0);
    attrs.accuracyMultiplier = g_kvItems.GetFloat("accuracy_multiplier", 1.0);
    attrs.reloadSpeedMultiplier = g_kvItems.GetFloat("reload_speed_multiplier", 1.0);
    attrs.healthBonus = g_kvItems.GetNum("health_bonus", 0);
    attrs.ammoBonus = g_kvItems.GetNum("ammo_bonus", 0);
    attrs.noScope = g_kvItems.GetNum("no_scope", 0) == 1;
    attrs.noCrits = g_kvItems.GetNum("no_crits", 0) == 1;
    attrs.movementSpeedMultiplier = g_kvItems.GetFloat("movement_speed_multiplier", 1.0);
    
    g_kvItems.Rewind();
    
    // 기본값이 아닌 속성이 하나라도 있으면 true
    return (attrs.damageMultiplier != 1.0 || 
            attrs.fireRateMultiplier != 1.0 || 
            attrs.chargeRateMultiplier != 1.0 ||
            attrs.accuracyMultiplier != 1.0 ||
            attrs.reloadSpeedMultiplier != 1.0 ||
            attrs.healthBonus != 0 ||
            attrs.ammoBonus != 0 ||
            attrs.noScope ||
            attrs.noCrits ||
            attrs.movementSpeedMultiplier != 1.0);
}

void UpdateReloadHUD(int client) {
    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (activeWeapon == -1) {
        SetHudTextParams(0.70, 0.85, 0.1, 255, 200, 100, 0);
        ShowSyncHudText(client, g_hReloadHudSync, "");
        return;
    }
    
    int slot = GetSlotFromWeapon(client, activeWeapon);
    if (slot == -1 || slot >= 3 || strlen(g_WeaponData[client][slot].weaponId) == 0) {
        SetHudTextParams(0.70, 0.85, 0.1, 255, 200, 100, 0);
        ShowSyncHudText(client, g_hReloadHudSync, "");
        return;
    }
    
    // 근접무기는 표시하지 않음
    if (g_WeaponData[client][slot].type == WEAPON_TYPE_MELEE) {
        SetHudTextParams(0.70, 0.85, 0.1, 255, 200, 100, 0);
        ShowSyncHudText(client, g_hReloadHudSync, "");
        return;
    }
    
    // 현재 활성 무기가 리로드 중일 때만 표시
    if (g_bReloading[client][slot]) {
        float currentTime = GetGameTime();
        float elapsed = currentTime - g_fReloadStartTime[client][slot];
        float remaining = g_fReloadDelay[client][slot] - elapsed;
        
        if (remaining > 0.0) {
            SetHudTextParams(0.70, 0.85, 1.1, 255, 200, 100, 255, 0, 0.0, 0.0, 0.0);
            ShowSyncHudText(client, g_hReloadHudSync, "재장전: %.1f초", remaining);
        } else {
            SetHudTextParams(0.70, 0.85, 0.1, 255, 200, 100, 0);
            ShowSyncHudText(client, g_hReloadHudSync, "");
        }
    } else {
        SetHudTextParams(0.70, 0.85, 0.1, 255, 200, 100, 0);
        ShowSyncHudText(client, g_hReloadHudSync, "");
    }
}

void SetWeaponAmmo(int weapon, int ammo) {
    if (!IsValidEntity(weapon)) {
        return;
    }
    
    // 근접무기인지 체크
    char className[64];
    GetEntityClassname(weapon, className, sizeof(className));
    if (StrContains(className, "melee") != -1 || 
        StrContains(className, "fists") != -1 || 
        StrContains(className, "club") != -1 ||
        StrContains(className, "knife") != -1 ||
        StrContains(className, "sword") != -1 ||
        StrContains(className, "bottle") != -1 ||
        StrContains(className, "bat") != -1 ||
        StrContains(className, "shovel") != -1) {
        return; // 근접무기는 탄약 설정 안 함
    }
    
    // 탄약 검증
    int finalAmmo = ammo;
    
    if (finalAmmo < 0) {
        finalAmmo = 0;
    }
    if (finalAmmo > 254) {
        finalAmmo = 254;
    }
    
    // 클립 탄약 설정
    if (HasEntProp(weapon, Prop_Send, "m_iClip1")) {
        SetEntProp(weapon, Prop_Send, "m_iClip1", finalAmmo);
    }
    
    if (HasEntProp(weapon, Prop_Data, "m_iClip1")) {
        SetEntProp(weapon, Prop_Data, "m_iClip1", finalAmmo);
    }
    
    // 탄약 재생성 비활성화
    TF2Attrib_SetByDefIndex(weapon, 78, 0.0);
    TF2Attrib_SetByDefIndex(weapon, 303, -1.0);
}

int GetSlotFromWeapon(int client, int weapon) {
    for (int slot = 0; slot < 3; slot++) {
        if (GetPlayerWeaponSlot(client, slot) == weapon) {
            return slot;
        }
    }
    return -1;
}

int GetDefaultItemIndex(const char[] className) {
    if (StrEqual(className, "tf_weapon_sniperrifle")) return 14;
    else if (StrEqual(className, "tf_weapon_smg")) return 16;
    else if (StrEqual(className, "tf_weapon_shotgun_primary")) return 9;
    else if (StrEqual(className, "tf_weapon_shotgun_soldier")) return 10;
    else if (StrEqual(className, "tf_weapon_shotgun_pyro")) return 12;
    else if (StrEqual(className, "tf_weapon_shotgun_hwg")) return 11;
    else if (StrEqual(className, "tf_weapon_pistol")) return 23;
    else if (StrEqual(className, "tf_weapon_revolver")) return 24;
    else if (StrEqual(className, "tf_weapon_club")) return 3;
    else if (StrEqual(className, "tf_weapon_knife")) return 4;
    else if (StrEqual(className, "tf_weapon_fists")) return 5;
    else if (StrEqual(className, "tf_weapon_shovel")) return 6;
    else if (StrEqual(className, "tf_weapon_bottle")) return 1;
    else if (StrEqual(className, "tf_weapon_sword")) return 132;
    else if (StrEqual(className, "tf_weapon_bat")) return 0;
    else if (StrEqual(className, "tf_weapon_scattergun")) return 13;
    else if (StrEqual(className, "tf_weapon_rocketlauncher")) return 18;
    else if (StrEqual(className, "tf_weapon_grenadelauncher")) return 19;
    else if (StrEqual(className, "tf_weapon_pipebomblauncher")) return 20;
    else if (StrEqual(className, "tf_weapon_flamethrower")) return 21;
    else if (StrEqual(className, "tf_weapon_minigun")) return 15;
    else if (StrEqual(className, "tf_weapon_crossbow")) return 305;
    else if (StrEqual(className, "tf_weapon_syringegun_medic")) return 17;
    
    return 0;
}

void StripWeapons(int client) {
    for (int slot = 0; slot < 5; slot++) {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon != -1) {
            RemovePlayerItem(client, weapon);
            RemoveEntity(weapon);
        }
    }
}

void GivePlayerFists(int client) {
    Handle hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
    
    if (hWeapon == null) return;
    
    TF2Items_SetClassname(hWeapon, "tf_weapon_fists");
    TF2Items_SetItemIndex(hWeapon, 5);
    TF2Items_SetLevel(hWeapon, 1);
    TF2Items_SetQuality(hWeapon, 0);
    
    int weapon = TF2Items_GiveNamedItem(client, hWeapon);
    delete hWeapon;
    
    if (weapon != -1) {
        EquipPlayerWeapon(client, weapon);
        SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", -1);
        SetEntProp(weapon, Prop_Send, "m_nModelIndexOverrides", -1, _, 0);
    }
}

void LoadItemsConfig() {
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/Dayz/items.cfg");
    
    if (g_kvItems != null) {
        delete g_kvItems;
    }
    
    g_kvItems = new KeyValues("Items");
    if (!g_kvItems.ImportFromFile(path)) {
        SetFailState("아이템 설정 파일을 불러올 수 없습니다: %s", path);
    }
}

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

// 포워드 핸들
Handle DayZ_OnWeaponEquip;

public void OnAllPluginsLoaded() {
    DayZ_OnWeaponEquip = FindConVar("DayZ_OnWeaponEquip");
}