#if defined _dayz_core_included
#endinput
#endif
#define _dayz_core_included

// 공통 상수 정의
#define PLUGIN_VERSION "1.0"
#define MAX_DROPPED_ITEMS 500
#define MAX_LOOT_BOXES 100
#define DEFAULT_KARMA 1000
#define DEFAULT_HUNGER 1000.0
#define DEFAULT_THIRST 1000.0
#define DEFAULT_STAMINA 100.0
#define SPRINT_SPEED_MULTIPLIER 1.3
#define SPRINT_DRAIN_RATE 3.0
#define SPRINT_MIN_STAMINA 10.0
#define PICKUP_DISTANCE 100.0
#define INVENTORY_SIZE 20
#define SPRINT_COOLDOWN 2.0
#define MAX_HEALTH 500
#define DROP_CLEANUP_TIME 300.0
#define LOOT_RESPAWN_TIME 600.0
#define MAX_BOX_ITEMS 20
#define LOOTBOX_MODEL "models/items/ammopack_medium.mdl"
#define EMPTY_WEAPON_SOUND "weapons/shotgun_empty.wav"

// 사운드 상수
#define SOUND_PICKUP "items/pickup_ammo_01.wav"
#define SOUND_DROP "items/spawn_item.wav"
#define SOUND_EAT "player/taunt_sandwich_bite.wav"
#define SOUND_DRINK "player/taunt_water_drink.wav"

// 열거형 정의
enum StatusEffect {
    STATUS_NONE = 0,
    STATUS_BLEEDING,
    STATUS_FRACTURE,
    STATUS_COLD
}

enum ItemType {
    ITEM_TYPE_WEAPON = 0,
    ITEM_TYPE_AMMO,
    ITEM_TYPE_FOOD,
    ITEM_TYPE_DRINK,
    ITEM_TYPE_MEDICAL,
    ITEM_TYPE_CRAFTING
}

enum WeaponType {
    WEAPON_TYPE_NONE,
    WEAPON_TYPE_RIFLE,
    WEAPON_TYPE_SHOTGUN,
    WEAPON_TYPE_PISTOL,
    WEAPON_TYPE_MELEE
}

// 구조체 정의
enum struct WeaponAttributes {
    float damageMultiplier;
    float fireRateMultiplier;
    float chargeRateMultiplier;
    float accuracyMultiplier;
    float reloadSpeedMultiplier;
    int healthBonus;
    int ammoBonus;
    bool noScope;
    bool noCrits;
    float movementSpeedMultiplier;
}

enum struct WeaponData {
    char weaponId[32];
    WeaponType type;
    int currentAmmo;
    int maxAmmo;
    int damage;
    int slotType;
}

enum struct LootBox {
    int entity;
    char boxId[32];
    float posX;
    float posY;
    float posZ;
    float angX;
    float angY;
    float angZ;
    float lastRespawnTime;
    bool isValid;
    bool hasItems;
}

enum struct InventorySlot {
    char itemId[32];
    int amount;
    bool isValid;
    WeaponData weaponData;
    int type;
}

enum struct DroppedItemInfo {
    int entity;
    char itemId[32];
    char name[64];
    int amount;
    float dropTime;
    bool isValid;
    WeaponData weaponData;
    int type;
}

enum struct ItemInfo {
    char itemId[32];
    char name[64];
    int amount;
    bool isValid;
    WeaponData weaponData;
}

// 네이티브 함수 선언
native bool DayZ_IsEnabled();
native bool DayZ_IsWaitingPeriod();
native int DayZ_GetPlayerKarma(int client);
native void DayZ_SetPlayerKarma(int client, int karma);
native float DayZ_GetPlayerHunger(int client);
native void DayZ_SetPlayerHunger(int client, float hunger);
native float DayZ_GetPlayerThirst(int client);
native void DayZ_SetPlayerThirst(int client, float thirst);
native float DayZ_GetPlayerStamina(int client);
native void DayZ_SetPlayerStamina(int client, float stamina);
native bool DayZ_HasInventorySpace(int client, int itemType = -1);
native bool DayZ_GivePlayerItem(int client, const char[] itemId, int amount = 1, int itemType = -1);
native bool DayZ_RemovePlayerItem(int client, const char[] itemId, int amount = 1, int itemType = -1);
native int DayZ_CountPlayerItems(int client, const char[] itemId);
native bool DayZ_HasWeapon(int client, int slot);
native void DayZ_GetWeaponId(int client, int slot, char[] buffer, int maxlength);

// 포워드 함수 선언
forward void DayZ_OnPlayerDataLoaded(int client);
forward void DayZ_OnPlayerStatusChange(int client, float hunger, float thirst, float stamina);
forward void DayZ_OnItemPickup(int client, const char[] itemId, int amount);
forward void DayZ_OnItemDrop(int client, const char[] itemId, int amount);
forward void DayZ_OnWeaponEquip(int client, int slot, const char[] weaponId);
forward void DayZ_OnStatusEffectApply(int client, StatusEffect effect);
forward void DayZ_OnStatusEffectRemove(int client, StatusEffect effect);

// 공용 라이브러리 설정
public SharedPlugin __pl_dayz_core = {
    name = "dayz_core",
    file = "dayz_mode.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_dayz_core_SetNTVOptional() {
    MarkNativeAsOptional("DayZ_IsEnabled");
    MarkNativeAsOptional("DayZ_IsWaitingPeriod");
    MarkNativeAsOptional("DayZ_GetPlayerKarma");
    MarkNativeAsOptional("DayZ_SetPlayerKarma");
    MarkNativeAsOptional("DayZ_GetPlayerHunger");
    MarkNativeAsOptional("DayZ_SetPlayerHunger");
    MarkNativeAsOptional("DayZ_GetPlayerThirst");
    MarkNativeAsOptional("DayZ_SetPlayerThirst");
    MarkNativeAsOptional("DayZ_GetPlayerStamina");
    MarkNativeAsOptional("DayZ_SetPlayerStamina");
    MarkNativeAsOptional("DayZ_HasInventorySpace");
    MarkNativeAsOptional("DayZ_GivePlayerItem");
    MarkNativeAsOptional("DayZ_RemovePlayerItem");
    MarkNativeAsOptional("DayZ_CountPlayerItems");
    MarkNativeAsOptional("DayZ_HasWeapon");
    MarkNativeAsOptional("DayZ_GetWeaponId");
}