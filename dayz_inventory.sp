#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#include "dayz/dayz_core.inc"

// 인벤토리 시스템 변수
InventorySlot g_PlayerInventory[MAXPLAYERS + 1][INVENTORY_SIZE];
KeyValues g_kvItems = null;

public Plugin myinfo = {
    name = "TF2 DayZ Mode - Inventory",
    author = "FinN",
    description = "DayZ Inventory System for Team Fortress 2",
    version = PLUGIN_VERSION,
    url = "https://steamcommunity.com/profiles/76561198041705012/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    // 네이티브 함수 등록
    CreateNative("DayZ_HasInventorySpace", Native_HasInventorySpace);
    CreateNative("DayZ_GivePlayerItem", Native_GivePlayerItem);
    CreateNative("DayZ_RemovePlayerItem", Native_RemovePlayerItem);
    CreateNative("DayZ_CountPlayerItems", Native_CountPlayerItems);
    
    RegPluginLibrary("dayz_inventory");
    return APLRes_Success;
}

public void OnPluginStart() {
    // 명령어 등록
    RegConsoleCmd("sm_inv", Command_Inventory, "인벤토리 열기");
    RegConsoleCmd("sm_inventory", Command_Inventory, "인벤토리 열기");
    
    // 관리자 명령어
    RegAdminCmd("sm_giveitem", Command_GiveItem, ADMFLAG_ROOT, "플레이어에게 아이템 지급");
    RegAdminCmd("sm_item", Command_GiveItem, ADMFLAG_ROOT, "플레이어에게 아이템 지급");
    
    // 설정 파일 로드
    LoadItemsConfig();
    
    // 클라이언트 초기화
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i)) {
            OnClientPutInServer(i);
        }
    }
    
    // 사운드 프리캐시
    PrecacheSound(SOUND_PICKUP);
    PrecacheSound(SOUND_EAT);
    PrecacheSound(SOUND_DRINK);
}

public void OnMapStart() {
    LoadItemsConfig();
    
    // 사운드 프리캐시
    PrecacheSound(SOUND_PICKUP);
    PrecacheSound(SOUND_EAT);
    PrecacheSound(SOUND_DRINK);
}

public void OnClientPutInServer(int client) {
    if (!IsValidClient(client)) return;
    
    // 인벤토리 초기화
    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        g_PlayerInventory[client][slot].isValid = false;
        g_PlayerInventory[client][slot].itemId[0] = '\0';
        g_PlayerInventory[client][slot].amount = 0;
        g_PlayerInventory[client][slot].type = 0;
        
        // 무기 데이터 초기화
        g_PlayerInventory[client][slot].weaponData.weaponId[0] = '\0';
        g_PlayerInventory[client][slot].weaponData.type = WEAPON_TYPE_NONE;
        g_PlayerInventory[client][slot].weaponData.currentAmmo = 0;
        g_PlayerInventory[client][slot].weaponData.maxAmmo = 0;
        g_PlayerInventory[client][slot].weaponData.damage = 0;
        g_PlayerInventory[client][slot].weaponData.slotType = 0;
    }
}

// 네이티브 함수 구현
public int Native_HasInventorySpace(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int itemType = GetNativeCell(2);
    
    if (!IsValidClient(client)) return false;
    
    int startSlot, endSlot;
    GetSlotRange(itemType, startSlot, endSlot);
    
    for (int slot = startSlot; slot < endSlot; slot++) {
        if (!g_PlayerInventory[client][slot].isValid) {
            return true;
        }
    }
    
    return false;
}

public int Native_GivePlayerItem(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    char itemId[32];
    GetNativeString(2, itemId, sizeof(itemId));
    int amount = GetNativeCell(3);
    int itemType = GetNativeCell(4);
    
    return GiveItem(client, itemId, amount, itemType);
}

public int Native_RemovePlayerItem(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    char itemId[32];
    GetNativeString(2, itemId, sizeof(itemId));
    int amount = GetNativeCell(3);
    int itemType = GetNativeCell(4);
    
    RemoveItem(client, itemId, amount, itemType);
    return true;
}

public int Native_CountPlayerItems(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    char itemId[32];
    GetNativeString(2, itemId, sizeof(itemId));
    
    return CountPlayerItems(client, itemId);
}

// 명령어 핸들러
public Action Command_Inventory(int client, int args) {
    if (!IsValidClient(client)) return Plugin_Handled;
    if (!DayZ_IsEnabled()) {
        PrintToChat(client, "\x04[데이즈]\x01 시스템이 비활성화되어 있습니다.");
        return Plugin_Handled;
    }
    
    ShowInventoryMenu(client);
    return Plugin_Handled;
}

public Action Command_GiveItem(int client, int args) {
    if (!IsValidAdmin(client)) {
        PrintToChat(client, "\x04[데이즈]\x01 이 명령어는 관리자만 사용할 수 있습니다.");
        return Plugin_Handled;
    }
    
    if (args < 2) {
        PrintToChat(client, "\x04[데이즈]\x01 사용법: !giveitem <대상> <아이템ID> [수량]");
        PrintToChat(client, "\x04[데이즈]\x01 예시: !giveitem @me medkit 1");
        return Plugin_Handled;
    }
    
    char targetArg[32], itemId[32], amountStr[16];
    GetCmdArg(1, targetArg, sizeof(targetArg));
    GetCmdArg(2, itemId, sizeof(itemId));
    
    int amount = 1;
    if (args >= 3) {
        GetCmdArg(3, amountStr, sizeof(amountStr));
        amount = StringToInt(amountStr);
        if (amount < 1) amount = 1;
    }
    
    if (!g_kvItems.JumpToKey(itemId)) {
        PrintToChat(client, "\x04[데이즈]\x01 존재하지 않는 아이템입니다: %s", itemId);
        return Plugin_Handled;
    }
    g_kvItems.Rewind();
    
    int target = -1;
    if (StrEqual(targetArg, "@me")) {
        target = client;
    } else {
        char targetName[MAX_TARGET_LENGTH];
        int targetList[MAXPLAYERS], targetCount;
        bool targetTranslate;
        
        if ((targetCount = ProcessTargetString(targetArg, client, targetList, MAXPLAYERS, 
            COMMAND_FILTER_ALIVE, targetName, sizeof(targetName), targetTranslate)) <= 0) {
            ReplyToTargetError(client, targetCount);
            return Plugin_Handled;
        }
        target = targetList[0];
    }
    
    if (!IsValidClient(target)) {
        PrintToChat(client, "\x04[데이즈]\x01 잘못된 대상입니다.");
        return Plugin_Handled;
    }
    
    if (GiveItem(target, itemId, amount)) {
        char itemName[64];
        g_kvItems.JumpToKey(itemId);
        g_kvItems.GetString("name", itemName, sizeof(itemName));
        g_kvItems.Rewind();
        
        PrintToChat(client, "\x04[데이즈]\x01 %N에게 %s x%d 지급 완료", target, itemName, amount);
        if (target != client) {
            PrintToChat(target, "\x04[데이즈]\x01 관리자가 당신에게 %s x%d 지급했습니다.", itemName, amount);
        }
    } else {
        PrintToChat(client, "\x04[데이즈]\x01 아이템 지급에 실패했습니다.");
    }
    
    return Plugin_Handled;
}

// 메뉴 함수
void ShowInventoryMenu(int client) {
    Menu menu = new Menu(MenuHandler_InventoryCategory);
    menu.SetTitle("▶ 인벤토리\n ");
    
    menu.AddItem("equipment", "장비 슬롯");
    menu.AddItem("consumables", "소모품 슬롯");
    menu.AddItem("ammo", "탄약 슬롯");
    menu.AddItem("materials", "재료 슬롯");
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_InventoryCategory(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_Select: {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            
            if (StrEqual(info, "equipment")) {
                ShowEquipmentMenu(param1);
            }
            else if (StrEqual(info, "consumables")) {
                ShowConsumablesMenu(param1);
            }
            else if (StrEqual(info, "ammo")) {
                ShowAmmoMenu(param1);
            }
            else if (StrEqual(info, "materials")) {
                ShowMaterialsMenu(param1);
            }
        }
        case MenuAction_End: {
            delete menu;
        }
    }
    return 0;
}

void ShowEquipmentMenu(int client) {
    Menu menu = new Menu(MenuHandler_Inventory);
    menu.SetTitle("▶ 장비 슬롯\n ");
    
    bool hasItems = false;
    char buffer[128];
    
    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        if (g_PlayerInventory[client][slot].isValid && g_PlayerInventory[client][slot].type == 0) {
            hasItems = true;
            
            char itemName[64];
            g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
            g_kvItems.GetString("name", itemName, sizeof(itemName), g_PlayerInventory[client][slot].itemId);
            g_kvItems.Rewind();
            
            Format(buffer, sizeof(buffer), "%s x%d", itemName, g_PlayerInventory[client][slot].amount);
            char slotStr[8];
            IntToString(slot, slotStr, sizeof(slotStr));
            menu.AddItem(slotStr, buffer);
        }
    }
    
    if (!hasItems) {
        menu.AddItem("", "장비 아이템이 없습니다", ITEMDRAW_DISABLED);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowConsumablesMenu(int client) {
    Menu menu = new Menu(MenuHandler_Inventory);
    menu.SetTitle("▶ 소모품 슬롯\n ");
    
    bool hasItems = false;
    char buffer[128];
    
    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        if (g_PlayerInventory[client][slot].isValid && g_PlayerInventory[client][slot].type == 1) {
            hasItems = true;
            
            char itemName[64];
            g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
            g_kvItems.GetString("name", itemName, sizeof(itemName), g_PlayerInventory[client][slot].itemId);
            g_kvItems.Rewind();
            
            Format(buffer, sizeof(buffer), "%s x%d", itemName, g_PlayerInventory[client][slot].amount);
            char slotStr[8];
            IntToString(slot, slotStr, sizeof(slotStr));
            menu.AddItem(slotStr, buffer);
        }
    }
    
    if (!hasItems) {
        menu.AddItem("", "소모품 아이템이 없습니다", ITEMDRAW_DISABLED);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowAmmoMenu(int client) {
    Menu menu = new Menu(MenuHandler_AmmoView);
    menu.SetTitle("▶ 탄약 슬롯\n ");
    
    bool hasItems = false;
    char buffer[128];
    
    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        if (g_PlayerInventory[client][slot].isValid) {
            char typeStr[32];
            g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
            g_kvItems.GetString("type", typeStr, sizeof(typeStr));
            g_kvItems.Rewind();
            
            if (StrEqual(typeStr, "ammo") || g_PlayerInventory[client][slot].type == 3) {
                hasItems = true;
                
                char itemName[64];
                g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
                g_kvItems.GetString("name", itemName, sizeof(itemName), g_PlayerInventory[client][slot].itemId);
                g_kvItems.Rewind();
                
                Format(buffer, sizeof(buffer), "%s x%d", itemName, g_PlayerInventory[client][slot].amount);
                menu.AddItem("", buffer, ITEMDRAW_DISABLED);
            }
        }
    }
    
    if (!hasItems) {
        menu.AddItem("", "탄약이 없습니다", ITEMDRAW_DISABLED);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowMaterialsMenu(int client) {
    Menu menu = new Menu(MenuHandler_Inventory);
    menu.SetTitle("▶ 재료 슬롯\n ");
    
    bool hasItems = false;
    char buffer[128];
    
    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        if (g_PlayerInventory[client][slot].isValid && g_PlayerInventory[client][slot].type == 2) {
            hasItems = true;
            
            char itemName[64];
            g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
            g_kvItems.GetString("name", itemName, sizeof(itemName), g_PlayerInventory[client][slot].itemId);
            g_kvItems.Rewind();
            
            Format(buffer, sizeof(buffer), "%s x%d", itemName, g_PlayerInventory[client][slot].amount);
            char slotStr[8];
            IntToString(slot, slotStr, sizeof(slotStr));
            menu.AddItem(slotStr, buffer);
        }
    }
    
    if (!hasItems) {
        menu.AddItem("", "재료 아이템이 없습니다", ITEMDRAW_DISABLED);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_AmmoView(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_Cancel: {
            if (param2 == MenuCancel_ExitBack) {
                ShowInventoryMenu(param1);
            }
        }
        case MenuAction_End: {
            delete menu;
        }
    }
    return 0;
}

public int MenuHandler_Inventory(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_Select: {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            int slot = StringToInt(info);
            
            ShowItemActionMenu(param1, slot);
        }
        case MenuAction_Cancel: {
            if (param2 == MenuCancel_ExitBack) {
                ShowInventoryMenu(param1);
            }
        }
        case MenuAction_End: {
            delete menu;
        }
    }
    return 0;
}

void ShowItemActionMenu(int client, int slot) {
    if (!IsValidClient(client) || !g_PlayerInventory[client][slot].isValid) {
        return;
    }
    
    Menu menu = new Menu(MenuHandler_ItemAction);
    char itemName[64];
    g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
    g_kvItems.GetString("name", itemName, sizeof(itemName));
    g_kvItems.Rewind();
    
    menu.SetTitle("%s x%d\n ", itemName, g_PlayerInventory[client][slot].amount);
    
    char slotStr[8];
    IntToString(slot, slotStr, sizeof(slotStr));
    
    menu.AddItem(slotStr, "사용하기");
    menu.AddItem(slotStr, "버리기");
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ItemAction(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_Select: {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            int slot = StringToInt(info);
            
            if (!IsValidClient(param1) || !g_PlayerInventory[param1][slot].isValid) {
                delete menu;
                return 0;
            }
            
            int itemType = g_PlayerInventory[param1][slot].type;
            
            switch (param2) {
                case 0: {  // 사용하기
                    UseItem(param1, slot);
                    
                    // 아이템 타입에 따라 해당 메뉴로 돌아가기
                    switch (itemType) {
                        case 0: ShowEquipmentMenu(param1);
                        case 1: ShowConsumablesMenu(param1);
                        case 2: ShowMaterialsMenu(param1);
                        default: ShowInventoryMenu(param1);
                    }
                }
                case 1: {  // 버리기
                    ShowDropItemMenu(param1, slot);
                }
            }
        }
        case MenuAction_Cancel: {
            if (param2 == MenuCancel_ExitBack) {
                ShowInventoryMenu(param1);
            }
        }
        case MenuAction_End: {
            delete menu;
        }
    }
    return 0;
}

void ShowDropItemMenu(int client, int slot) {
    if (!IsValidClient(client) || !g_PlayerInventory[client][slot].isValid) {
        return;
    }
    
    Menu menu = new Menu(MenuHandler_DropItem);
    
    char itemName[64];
    g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
    g_kvItems.GetString("name", itemName, sizeof(itemName));
    g_kvItems.Rewind();
    
    menu.SetTitle("▶ %s x%d 버리기\n ", itemName, g_PlayerInventory[client][slot].amount);
    
    char info[32];
    Format(info, sizeof(info), "%d,1", slot);
    menu.AddItem(info, "1개 버리기");
    
    if (g_PlayerInventory[client][slot].amount > 1) {
        Format(info, sizeof(info), "%d,%d", slot, g_PlayerInventory[client][slot].amount);
        menu.AddItem(info, "전부 버리기");
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_DropItem(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_Select: {
            char info[32], parts[2][16];
            menu.GetItem(param2, info, sizeof(info));
            ExplodeString(info, ",", parts, sizeof(parts), sizeof(parts[]));
            
            int slot = StringToInt(parts[0]);
            int amount = StringToInt(parts[1]);
            
            if (!IsValidClient(param1) || !g_PlayerInventory[param1][slot].isValid) {
                delete menu;
                return 0;
            }
            
            DropInventoryItem(param1, slot, amount);
            ShowInventoryMenu(param1);
        }
        case MenuAction_Cancel: {
            if (param2 == MenuCancel_ExitBack) {
                ShowInventoryMenu(param1);
            }
        }
        case MenuAction_End: {
            delete menu;
        }
    }
    return 0;
}

// 핵심 기능 함수
bool GiveItem(int client, const char[] itemId, int amount = 1, int itemType = -1) {
    if (!IsValidClient(client)) return false;

    if (!g_kvItems.JumpToKey(itemId)) {
        PrintToChat(client, "\x04[데이즈]\x01 아이템 정보를 찾을 수 없습니다!");
        return false;
    }

    char typeStr[32];
    g_kvItems.GetString("type", typeStr, sizeof(typeStr));
    
    int slotType;
    if (itemType != -1) {
        slotType = itemType;
    } else {
        // 타입 자동 판별
        if (StrEqual(typeStr, "weapon") || StrEqual(typeStr, "armor") || StrEqual(typeStr, "equipment")) {
            slotType = 0;  // 장비
        }
        else if (StrEqual(typeStr, "food") || StrEqual(typeStr, "drink") || 
                 StrEqual(typeStr, "medical") || StrEqual(typeStr, "stamina")) {
            slotType = 1;  // 소모품
        }
        else if (StrEqual(typeStr, "material") || StrEqual(typeStr, "crafting")) {
            slotType = 2;  // 재료
        }
        else if (StrEqual(typeStr, "ammo")) {
            slotType = 3;  // 탄약
        }
        else {
            slotType = 1;  // 기본값: 소모품
        }
    }

    g_kvItems.Rewind();
    
    // 이미 같은 아이템이 있는지 확인
    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        if (g_PlayerInventory[client][slot].isValid && 
            StrEqual(g_PlayerInventory[client][slot].itemId, itemId) &&
            g_PlayerInventory[client][slot].type == slotType) {
            
            g_PlayerInventory[client][slot].amount += amount;
            EmitSoundToClient(client, SOUND_PICKUP);
            
            // 포워드 호출
            Call_StartForward(DayZ_OnItemPickup);
            Call_PushCell(client);
            Call_PushString(itemId);
            Call_PushCell(amount);
            Call_Finish();
            
            return true;
        }
    }

    // 빈 슬롯 찾기
    int startSlot, endSlot;
    GetSlotRange(slotType, startSlot, endSlot);
    
    for (int slot = startSlot; slot < endSlot; slot++) {
        if (!g_PlayerInventory[client][slot].isValid) {
            strcopy(g_PlayerInventory[client][slot].itemId, 32, itemId);
            g_PlayerInventory[client][slot].amount = amount;
            g_PlayerInventory[client][slot].isValid = true;
            g_PlayerInventory[client][slot].type = slotType;
            
            EmitSoundToClient(client, SOUND_PICKUP);
            
            // 포워드 호출
            Call_StartForward(DayZ_OnItemPickup);
            Call_PushCell(client);
            Call_PushString(itemId);
            Call_PushCell(amount);
            Call_Finish();
            
            return true;
        }
    }

    PrintToChat(client, "\x04[데이즈]\x01 인벤토리가 가득 찼습니다!");
    return false;
}

void UseItem(int client, int slot) {
    if (!IsValidClient(client) || !g_PlayerInventory[client][slot].isValid) 
        return;

    char itemId[32];
    strcopy(itemId, sizeof(itemId), g_PlayerInventory[client][slot].itemId);

    if (!g_kvItems.JumpToKey(itemId)) {
        PrintToChat(client, "\x04[데이즈]\x01 아이템 정보를 찾을 수 없습니다!");
        return;
    }

    char typeStr[32], itemName[64];
    g_kvItems.GetString("type", typeStr, sizeof(typeStr));
    g_kvItems.GetString("name", itemName, sizeof(itemName));
    
    // 다중 회복 값들 가져오기
    float healthValue = g_kvItems.GetFloat("health_value", 0.0);
    float hungerValue = g_kvItems.GetFloat("hunger_value", 0.0);
    float thirstValue = g_kvItems.GetFloat("thirst_value", 0.0);
    float staminaValue = g_kvItems.GetFloat("stamina_value", 0.0);
    
    // 기존 호환성을 위한 value 처리
    float legacyValue = g_kvItems.GetFloat("value", 0.0);
    
    g_kvItems.Rewind();

    // 무기 타입 처리 (다른 플러그인에서 처리)
    if (StrEqual(typeStr, "weapon")) {
        PrintToChat(client, "\x04[데이즈]\x01 무기는 무기 시스템에서 처리됩니다.");
        return;
    }
    
    // 치료 아이템 처리 (상태이상 관련은 메인 플러그인에서 처리)
    bool itemUsed = false;
    char effectMessage[256] = "";
    char tempMessage[64];
    
    // 새로운 다중 회복 시스템
    if (healthValue > 0.0) {
        // 체력 회복은 메인 플러그인을 통해 처리
        Format(tempMessage, sizeof(tempMessage), "체력 +%d", RoundToFloor(healthValue));
        if (strlen(effectMessage) > 0) {
            Format(effectMessage, sizeof(effectMessage), "%s, %s", effectMessage, tempMessage);
        } else {
            strcopy(effectMessage, sizeof(effectMessage), tempMessage);
        }
        itemUsed = true;
    }
    
    if (hungerValue > 0.0) {
        float currentHunger = DayZ_GetPlayerHunger(client);
        DayZ_SetPlayerHunger(client, FloatMin(DEFAULT_HUNGER, currentHunger + hungerValue));
        
        Format(tempMessage, sizeof(tempMessage), "배고픔 +%.0f", hungerValue);
        if (strlen(effectMessage) > 0) {
            Format(effectMessage, sizeof(effectMessage), "%s, %s", effectMessage, tempMessage);
        } else {
            strcopy(effectMessage, sizeof(effectMessage), tempMessage);
        }
        itemUsed = true;
    }
    
    if (thirstValue > 0.0) {
        float currentThirst = DayZ_GetPlayerThirst(client);
        DayZ_SetPlayerThirst(client, FloatMin(DEFAULT_THIRST, currentThirst + thirstValue));
        
        Format(tempMessage, sizeof(tempMessage), "갈증 +%.0f", thirstValue);
        if (strlen(effectMessage) > 0) {
            Format(effectMessage, sizeof(effectMessage), "%s, %s", effectMessage, tempMessage);
        } else {
            strcopy(effectMessage, sizeof(effectMessage), tempMessage);
        }
        itemUsed = true;
    }
    
    if (staminaValue > 0.0) {
        float currentStamina = DayZ_GetPlayerStamina(client);
        DayZ_SetPlayerStamina(client, FloatMin(DEFAULT_STAMINA, currentStamina + staminaValue));
        
        Format(tempMessage, sizeof(tempMessage), "스태미나 +%.0f", staminaValue);
        if (strlen(effectMessage) > 0) {
            Format(effectMessage, sizeof(effectMessage), "%s, %s", effectMessage, tempMessage);
        } else {
            strcopy(effectMessage, sizeof(effectMessage), tempMessage);
        }
        itemUsed = true;
    }
    
    // 기존 타입 기반 시스템 (새로운 값이 없을 때만 사용)
    if (!itemUsed && legacyValue > 0.0) {
        if (StrEqual(typeStr, "food")) {
            float currentHunger = DayZ_GetPlayerHunger(client);
            DayZ_SetPlayerHunger(client, FloatMin(DEFAULT_HUNGER, currentHunger + legacyValue));
            Format(effectMessage, sizeof(effectMessage), "배고픔 +%.0f", legacyValue);
            itemUsed = true;
        }
        else if (StrEqual(typeStr, "drink")) {
            float currentThirst = DayZ_GetPlayerThirst(client);
            DayZ_SetPlayerThirst(client, FloatMin(DEFAULT_THIRST, currentThirst + legacyValue));
            Format(effectMessage, sizeof(effectMessage), "갈증 +%.0f", legacyValue);
            itemUsed = true;
        }
        else if (StrEqual(typeStr, "stamina")) {
            float currentStamina = DayZ_GetPlayerStamina(client);
            DayZ_SetPlayerStamina(client, FloatMin(DEFAULT_STAMINA, currentStamina + legacyValue));
            Format(effectMessage, sizeof(effectMessage), "스태미나 +%.0f", legacyValue);
            itemUsed = true;
        }
    }
    
    // 아이템 사용 완료 처리
    if (itemUsed) {
        // 적절한 효과음 재생
        if (hungerValue > 0.0 || StrEqual(typeStr, "food")) {
            EmitSoundToClient(client, SOUND_EAT);
        }
        else if (thirstValue > 0.0 || staminaValue > 0.0 || StrEqual(typeStr, "drink") || StrEqual(typeStr, "stamina")) {
            EmitSoundToClient(client, SOUND_DRINK);
        }
        else {
            EmitSoundToClient(client, SOUND_PICKUP);
        }
        
        // 메시지 출력
        PrintToChat(client, "\x04[데이즈]\x01 %s을(를) 사용했습니다. (%s)", itemName, effectMessage);
        
        // 인벤토리에서 아이템 제거
        RemoveItem(client, itemId, 1, g_PlayerInventory[client][slot].type);
    } else {
        PrintToChat(client, "\x04[데이즈]\x01 이 아이템은 사용할 수 없습니다.");
    }
}

void RemoveItem(int client, const char[] itemId, int amount = 1, int itemType = -1) {
    if (!IsValidClient(client)) return;

    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        if (g_PlayerInventory[client][slot].isValid && 
            StrEqual(g_PlayerInventory[client][slot].itemId, itemId) &&
            (itemType == -1 || g_PlayerInventory[client][slot].type == itemType)) {
            
            g_PlayerInventory[client][slot].amount -= amount;
            
            if (g_PlayerInventory[client][slot].amount <= 0) {
                g_PlayerInventory[client][slot].isValid = false;
                g_PlayerInventory[client][slot].amount = 0;
                g_PlayerInventory[client][slot].itemId[0] = '\0';
            }
            
            // 포워드 호출
            Call_StartForward(DayZ_OnItemDrop);
            Call_PushCell(client);
            Call_PushString(itemId);
            Call_PushCell(amount);
            Call_Finish();
            
            return;
        }
    }
}

int CountPlayerItems(int client, const char[] itemId) {
    int count = 0;
    
    for (int slot = 0; slot < INVENTORY_SIZE; slot++) {
        if (g_PlayerInventory[client][slot].isValid && StrEqual(g_PlayerInventory[client][slot].itemId, itemId)) {
            count += g_PlayerInventory[client][slot].amount;
        }
    }
    
    return count;
}

void DropInventoryItem(int client, int slot, int amount) {
    if (!IsValidClient(client) || !g_PlayerInventory[client][slot].isValid || amount <= 0) return;
    
    float dropPos[3], angles[3];
    GetClientEyePosition(client, dropPos);
    GetClientEyeAngles(client, angles);
    
    float direction[3];
    GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
    ScaleVector(direction, 50.0);
    AddVectors(dropPos, direction, dropPos);
    
    // 드롭 아이템 생성은 다른 플러그인에서 처리
    
    // 플레이어 인벤토리에서 제거
    int dropAmount = (amount > g_PlayerInventory[client][slot].amount) ? 
                      g_PlayerInventory[client][slot].amount : amount;
    
    g_PlayerInventory[client][slot].amount -= dropAmount;
    if (g_PlayerInventory[client][slot].amount <= 0) {
        g_PlayerInventory[client][slot].isValid = false;
    }
    
    char itemName[64];
    g_kvItems.JumpToKey(g_PlayerInventory[client][slot].itemId);
    g_kvItems.GetString("name", itemName, sizeof(itemName));
    g_kvItems.Rewind();
    
    PrintToChat(client, "\x04[데이즈]\x01 %s x%d을(를) 버렸습니다.", itemName, dropAmount);
    EmitSoundToClient(client, SOUND_DROP);
    
    // 포워드 호출
    Call_StartForward(DayZ_OnItemDrop);
    Call_PushCell(client);
    Call_PushString(g_PlayerInventory[client][slot].itemId);
    Call_PushCell(dropAmount);
    Call_Finish();
}

void GetSlotRange(int itemType, int &startSlot, int &endSlot) {
    switch (itemType) {
        case 0: {  // 장비
            startSlot = 0;
            endSlot = INVENTORY_SIZE/4;
        }
        case 1: {  // 소모품
            startSlot = INVENTORY_SIZE/4;
            endSlot = INVENTORY_SIZE/2;
        }
        case 2: {  // 재료
            startSlot = INVENTORY_SIZE/2;
            endSlot = (INVENTORY_SIZE/4) * 3;
        }
        case 3: {  // 탄약
            startSlot = (INVENTORY_SIZE/4) * 3;
            endSlot = INVENTORY_SIZE;
        }
        default: {
            startSlot = 0;
            endSlot = INVENTORY_SIZE;
        }
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

bool IsValidAdmin(int client) {
    return (IsValidClient(client) && CheckCommandAccess(client, "sm_admin", ADMFLAG_ROOT));
}

float FloatMin(float a, float b) {
    return (a < b) ? a : b;
}

float FloatMax(float a, float b) {
    return (a > b) ? a : b;
}

// 포워드 핸들 가져오기
Handle DayZ_OnItemPickup;
Handle DayZ_OnItemDrop;

public void OnAllPluginsLoaded() {
    DayZ_OnItemPickup = FindConVar("DayZ_OnItemPickup");
    DayZ_OnItemDrop = FindConVar("DayZ_OnItemDrop");
}