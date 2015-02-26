// ---- Preprocessor -----------------------------------------------------------
#pragma semicolon 1 

// ---- Includes ---------------------------------------------------------------
#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf2>
#include <tf2items>
#include <tf2attributes>
#include <steamtools>

//I use this so the compiler will warn about the old syntax
#pragma newdecls required

#include <dodgeball>

// ---- Defines ----------------------------------------------------------------
#define DB_VERSION "0.2.0"
#define PLAYERCOND_SPYCLOAK (1<<4)
#define MAXGENERIC 25
#define MAXMULTICOLORHUD 5
#define MAXHUDNUMBER
#define TEAM_RED 2
#define TEAM_BLUE 3
#define CLASS_PYRO 7
#define CLASS_SPY 8

#define SOUND_ALERT_VOL	0.8
#define HUD_LINE_SEPARATION 0.03

// ---- Variables --------------------------------------------------------------
bool g_isDBmap = false;
bool g_onPreparation = false;
bool g_roundActive = false;
bool g_canSpawn = false;
int g_lastSpawned = false;
int g_BlueSpawn = -1;
int g_RedSpawn = -1;
Handle g_HudSyncs[MAXHUDNUMBER];
char g_mainfile[PLATFORM_MAX_PATH];
char g_rocketclasses[PLATFORM_MAX_PATH];
	

// ---- Plugin's Configuration -------------------------------------------------
float g_player_speed;
bool g_pyro_only;
bool g_hud_show;
float g_hud_x;
float g_hud_y;
char g_hud_color[32];
char g_hud_aimed_text[PLATFORM_MAX_PATH];
char g_hud_aimed_color[32];

//Multi rocket color
bool g_allow_multirocketcolor;
char g_mrc_name[MAXMULTICOLORHUD][MAX_NAME_LENGTH];
char g_mrc_color[MAXMULTICOLORHUD][32];
char g_mrc_trail[MAXMULTICOLORHUD][PLATFORM_MAX_PATH];
bool g_mrc_applycolor_model[MAXMULTICOLORHUD];
bool g_mrc_applycolor_trail[MAXMULTICOLORHUD];

//Sound-config
StringMap g_SndRoundStart;
StringMap g_SndOnDeath;
float g_OnKillDelay;
StringMap g_SndOnKill;
StringMap g_SndLastAlive;

//Flamethrower restriction
StringMap g_RestrictedWeps;

//Command-config
StringMap g_CommandToBlock;
StringMap g_BlockOnlyOnPreparation;


//Spawner
int g_max_rockets;
float g_spawn_delay;
StringMap g_class_chance;

//Rocket Classes and entities (will be an struct in the future)
RocketClass g_RocketClass[MAXROCKETCLASS];
int g_RocketClass_count;
RocketEnt g_RocketEnt[MAXROCKETS];


// ---- Server's CVars Management ----------------------------------------------
Handle db_airdash;
Handle db_push;
Handle db_burstammo;

int db_airdash_def = 1;
int db_push_def = 1;
int db_burstammo_def = 1;

// ---- Plugin's Information ---------------------------------------------------
public Plugin myinfo =
{
	name = "[TF2] Dodgeball Redux",
	author = "Classic",
	description = "Dodgeball plugin for TF2",
	version = DB_VERSION,
	url = "http://www.clangs.com.ar"
};

/* OnPluginStart()
**
** When the plugin is loaded.
** -------------------------------------------------------------------------- */
public void OnPluginStart()
{
	//Cvars
	CreateConVar("sm_db_version", DB_VERSION, "Dogdeball Redux Version.", FCVAR_REPLICATED | FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	
	//Creation of Tries
	g_CommandToBlock = CreateTrie();
	g_BlockOnlyOnPreparation = CreateTrie();
	g_SndRoundStart = CreateTrie();
	g_SndOnDeath = CreateTrie();
	g_SndOnKill = CreateTrie();
	g_SndLastAlive = CreateTrie();
	g_RestrictedWeps = CreateTrie();
	
	//Server's Cvars
	db_airdash = FindConVar("tf_scout_air_dash_count");
	db_push = FindConVar("tf_avoidteammates_pushaway");
	db_burstammo = FindConVar("tf_flamethrower_burstammo");

	//HUD
	for(int i = 0; i < MAXHUDNUMBER; i++)
		g_HudSyncs[i]= CreateHudSynchronizer();

	//Rocket classes
	for(int i = 0; i < MAXROCKETCLASS; ++i 
		g_RocketClass[i] = RocketClass(i);
	//Rocket entities
	for(int i = 0; i < MAXROCKETS; ++i 
		g_RocketEnt[i] = RocketEnt(i);
		
	//Hooks
	HookEvent("teamplay_round_start", OnPrepartionStart);
	HookEvent("arena_round_start", OnRoundStart); 
	HookEvent("post_inventory_application", OnPlayerInventory);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("teamplay_round_win", OnRoundEnd);
	HookEvent("teamplay_round_stalemate", OnRoundEnd);
	
	BuildPath(Path_SM, g_mainfile, PLATFORM_MAX_PATH, "data/dodgeball/dodgeball.cfg");
	BuildPath(Path_SM, g_rocketclasses, PLATFORM_MAX_PATH, "data/dodgeball/rocketclasses.cfg");
}


/* OnMapStart()
**
** Here we reset every global variable, and we check if the current map is a dodgeball map.
** If it is a db map, we get the cvars def. values and the we set up our own values.
** -------------------------------------------------------------------------- */
public void OnMapStart()
{	
	char mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	if (strncmp(mapname, "db_", 3, false) == 0 || (strncmp(mapname, "tfdb_", 5, false) == 0) )
	{
		LogMessage("[DB] Dodgeball map detected. Enabling Dodgeball Gamemode.");
		g_isDBmap = true;
		Steam_SetGameDescription("Dodgeball Redux");
		AddServerTag("dodgeball");
		
		LoadRocketClasses();
		LoadConfigs();
		LoadMapConfigs();
		
		PrecacheFiles();
		ProcessListeners();
	}
 	else
	{
		LogMessage("[DB] Current map is not a Dodgeball map. Disabling Dodgeball Gamemode.");
		RemoveServerTag("dodgeball");
		g_isDBmap = false;
		Steam_SetGameDescription("Team Fortress");	
	}
}

/* OnMapEnd()
**
** Here we reset the server's cvars to their default values.
** -------------------------------------------------------------------------- */
public OnMapEnd()
{
	ResetCvars();
}

/* LoadRocketClasses()
**
** Here we parse data/dodgeball/rocketclasses.cfg
** -------------------------------------------------------------------------- */
void LoadRocketClasses()
{
	if(!FileExists(g_rocketclasses))
	{
		SetFailState("Configuration file %s not found!", g_rocketclasses);
		return;
	}
	KeyValues kv =  CreateKeyValues("rocketclasses");
	if(kv.ImportFromFile(g_rocketclasses))
	{
		SetFailState("Improper structure for configuration file %s!", g_rocketclasses);
		return;
	}
	if(!kv.JumpToKey("default"))
	{
		SetFailState("Missing default section on configuration file %s!", g_rocketclasses);
		return;
	}
	RocketClass defClass = RocketClass(DEF_C);
	char name[MAX_NAME_LENGTH], auxPath[PLATFORM_MAX_PATH];
	//Rocket Name (section name)
	kv.GetSectionName(name,MAX_NAME_LENGTH);
	defClass.SetName(name);
	//Trail
	kv.GetString("Trail",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetTrail(auxPath);
	//Model
	kv.GetString("Model",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetModel(auxPath);
	defClass.size = kv.GetFloat("ModelSize",1.0);
	defClass.sizeinc = kv.GetFloat("DeflectSizeInc",0.0);
	//Damage
	defClass.damage = kv.GetFloat("BaseDamage",200.0);
	defClass.damageinc = kv.GetFloat("DeflectDamageInc",0.0);
	//Speed
	defClass.speed = kv.GetFloat("BaseSpeed",1100.0);
	defClass.speedinc = kv.GetFloat("DeflectSpeedInc",50.0);
	//Turnrate
	defClass.turnrate = kv.GetFloat("TurnRate",0.05);
	defClass.turnrateinc = kv.GetFloat("DeflectTurnRateInc",0.005);
	//On deflect
	defClass.deflectdelay = kv.GetFloat("DeflectDelay",0.1);
	defClass.targetclosest = view_as<bool>kv.GetNum("TargetClosest",0);
	defClass.aimed = view_as<bool>kv.GetNum("AllowAimed",0);
	defClass.aimedspeed = kv.GetFloat("AimedSpeed",2500.0);
	//Bounce
	defClass.maxbounce = kv.GetNum("MaxBounce",10);
	defClass.bouncedelay = kv.GetFloat("BouceDelay",0.1);
	
	//Sounds
	if(kv.JumpToKey("sounds"))
	{
		//Spawn
		defClass.snd_spawn_use = view_as<bool>kv.GetNum("PlaySpawnSound",1);
		kv.GetString("SpawnSound",auxPath,PLATFORM_MAX_PATH,"");
		defClass.SetSndSpawn(auxPath);
		//Alert
		defClass.snd_alert_use = view_as<bool>kv.GetNum("PlayAlertSound",1);
		kv.GetString("AlertSound",auxPath,PLATFORM_MAX_PATH,"");
		defClass.SetSndAlert(auxPath);
		//Deflect
		defClass.snd_deflect_use = view_as<bool>kv.GetNum("PlayDeflectSound",1);
		kv.GetString("RedDeflectSound",auxPath,PLATFORM_MAX_PATH,"");
		defClass.SetSndDeflectRed(auxPath);
		kv.GetString("BlueDeflectSound",auxPath,PLATFORM_MAX_PATH,"");
		defClass.SetSndDeflectBlue(auxPath);
		//Beep
		defClass.snd_beep_use = view_as<bool>kv.GetNum("PlayBeepSound",1);
		kv.GetString("BeepSound",auxPath,PLATFORM_MAX_PATH,"");
		defClass.SetSndBeep(auxPath);
		defClass.snd_beep_delay = kv.GetFloat("BeepInterval",1.0);
		//Aimed
		defClass.snd_aimed_use = view_as<bool>kv.GetNum("PlayAimedSound",1);
		kv.GetString("AimedSound",auxPath,PLATFORM_MAX_PATH,"");
		defClass.SetSndAimed(auxPath);
		kv.GoBack();
	}
	//Explosion
	if(kv.JumpToKey("explosion"))
	{
		defClass.exp_use = view_as<bool>kv.GetNum("CreateBigExplosion",0);
		defClass.exp_damage = kv.GetNum("Damage",200);
		defClass.exp_push = kv.GetNum("PushStrength",1000);
		defClass.exp_radius = kv.GetNum("Radius",1000);
		defClass.exp_fallof = kv.GetNum("FallOfRadius",600);
		kv.GoBack();
	}
	
	
	//Here we read all the classes
	if(!kv.JumpToKey("Classes"))
	{
		SetFailState("Missing Classes section on configuration file %s!", g_rocketclasses);
		return;
	}
	int count = 0;
	kv.GotoFirstSubKey();
	do
    {
		//Rocket Name (section name)
		kv.GetSectionName(name,MAX_NAME_LENGTH);
		g_RocketClass[count].SetName(name);
		//Trail
		defClass.GetTrail(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("Trail",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetTrail(auxPath);
		//Model
		defClass.GetModel(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("Model",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetModel(auxPath);
		g_RocketClass[count].size = kv.GetFloat("ModelSize",defClass.size);
		g_RocketClass[count].sizeinc = kv.GetFloat("DeflectSizeInc",defClass.sizeinc);
		//Damage
		g_RocketClass[count].damage = kv.GetFloat("BaseDamage",defClass.damage);
		g_RocketClass[count].damageinc = kv.GetFloat("DeflectDamageInc",defClass.damageinc);
		//Speed
		g_RocketClass[count].speed = kv.GetFloat("BaseSpeed",defClass.speed);
		g_RocketClass[count].speedinc = kv.GetFloat("DeflectSpeedInc",defClass.speedinc);
		//Turnrate
		g_RocketClass[count].turnrate = kv.GetFloat("TurnRate",defClass.turnrate);
		g_RocketClass[count].turnrateinc = kv.GetFloat("DeflectTurnRateInc",defClass.turnrateinc);
		//On deflect
		g_RocketClass[count].deflectdelay = kv.GetFloat("DeflectDelay",defClass.deflectdelay);
		g_RocketClass[count].targetclosest = view_as<bool>kv.GetNum("TargetClosest",defClass.targetclosest);
		g_RocketClass[count].aimed = view_as<bool>kv.GetNum("AllowAimed",defClass.aimed);
		g_RocketClass[count].aimedspeed = kv.GetFloat("AimedSpeed",defClass.aimedspeed);
		//Bounce
		g_RocketClass[count].maxbounce = kv.GetNum("MaxBounce",defClass.maxbounce);
		g_RocketClass[count].bouncedelay = kv.GetFloat("BouceDelay",defClass.bouncedelay);
		
		//Sounds
		if(kv.JumpToKey("sounds"))
		{
			//Spawn
			g_RocketClass[count].snd_spawn_use = view_as<bool>kv.GetNum("PlaySpawnSound",defClass.snd_spawn_use);
			defClass.GetSndSpawn(auxPath,PLATFORM_MAX_PATH);
			kv.GetString("SpawnSound",auxPath,PLATFORM_MAX_PATH,auxPath);
			g_RocketClass[count].SetSndSpawn(auxPath);
			//Alert
			g_RocketClass[count].snd_alert_use = view_as<bool>kv.GetNum("PlayAlertSound",defClass.snd_alert_use);
			defClass.GetSndAlert(auxPath,PLATFORM_MAX_PATH);
			kv.GetString("AlertSound",auxPath,PLATFORM_MAX_PATH,auxPath);
			g_RocketClass[count].SetSndAlert(auxPath);
			//Deflect
			g_RocketClass[count].snd_deflect_use = view_as<bool>kv.GetNum("PlayDeflectSound",defClass.snd_deflect_use);
			defClass.GetSndDeflectRed(auxPath,PLATFORM_MAX_PATH);
			kv.GetString("RedDeflectSound",auxPath,PLATFORM_MAX_PATH,auxPath);
			g_RocketClass[count].SetSndDeflectRed(auxPath);
			defClass.GetSndDeflectBlue(auxPath,PLATFORM_MAX_PATH);
			kv.GetString("BlueDeflectSound",auxPath,PLATFORM_MAX_PATH,auxPath);
			g_RocketClass[count].SetSndDeflectBlue(auxPath);
			//Beep
			g_RocketClass[count].snd_beep_use = view_as<bool>kv.GetNum("PlayBeepSound",defClass.snd_beep_use);
			defClass.GetSndBeep(auxPath,PLATFORM_MAX_PATH);
			kv.GetString("BeepSound",auxPath,PLATFORM_MAX_PATH,auxPath);
			g_RocketClass[count].SetSndBeep(auxPath);
			g_RocketClass[count].snd_beep_delay = kv.GetFloat("BeepInterval",defClass.snd_beep_delay);
			//Aimed
			g_RocketClass[count].snd_aimed_use = view_as<bool>kv.GetNum("PlayAimedSound",defClass.snd_aimed_use);
			defClass.GetSndAimed(auxPath,PLATFORM_MAX_PATH);
			kv.GetString("AimedSound",auxPath,PLATFORM_MAX_PATH,auxPath);
			g_RocketClass[count].SetSndAimed(auxPath);
			kv.GoBack();
		}
		//Explosion
		if(kv.JumpToKey("explosion"))
		{
			g_RocketClass[count].exp_use = view_as<bool>kv.GetNum("CreateBigExplosion",defClass.exp_use);
			g_RocketClass[count].exp_damage = kv.GetNum("Damage",defClass.exp_damage);
			g_RocketClass[count].exp_push = kv.GetNum("PushStrength",defClass.exp_push);
			g_RocketClass[count].exp_radius = kv.GetNum("Radius",defClass.exp_radius);
			g_RocketClass[count].exp_fallof = kv.GetNum("FallOfRadius",defClass.exp_fallof);
			kv.GoBack();
		}
		count++;
	}
    while (kv.GotoNextKey() && count < MAXROCKETCLASS);
	delete kv;
	g_RocketClass_count = count;
	LogMessage("[DB] Loaded %d rocket classes.");
		
}

/* LoadConfigs()
**
** Here we parse data/dodgeball/dodgeball.cfg
** -------------------------------------------------------------------------- */
void LoadConfigs()
{
	if(!FileExists(g_mainfile))
	{
		SetFailState("Configuration file %s not found!", g_mainfile);
		return;
	}
	KeyValues kv =  CreateKeyValues("dodgeball");
	if(kv.ImportFromFile(g_mainfile))
	{
		SetFailState("Improper structure for configuration file %s!", g_mainfile);
		return;
	}
	//Here we clean the Tries
	g_SndRoundStart.Clear();
	g_SndOnDeath.Clear();
	g_SndOnKill.Clear();
	g_SndLastAlive.Clear();
	g_RestrictedWeps.Clear();
	g_CommandToBlock.Clear();
	g_BlockOnlyOnPreparation.Clear();
	g_class_chance.Clear();
	
	//Main configuration
	g_player_speed = kv.GetFloat("PlayerSpeed", 300.0);
	g_pyro_only = view_as<bool>kv.GetNum("OnlyPyro",0);
	g_hud_show = view_as<bool>kv.GetNum("ShowHud",0);
	g_hud_x = kv.GetFloat("Xpos", 0.03);
	g_hud_y = kv.GetFloat("Ypos", 0.21);
	kv.GetString("color",g_hud_color,32,"63 255 127");
	kv.GetString("supershottext",g_hud_aimed_text,PLATFORM_MAX_PATH,"Super Shot!");
	kv.GetString("supershotcolor",g_hud_aimed_color,32,"63 255 127");
	
	if(kv.JumpToKey("spawner"))
	{
		g_max_rockets = kv.GetNum("MaxRockets", 2);
		g_spawn_delay = kv.GetFloat("SpawnDelay"2.0);
		if(kv.JumpToKey("chances"))
		{
			char rocketname[MAX_NAME_LENGTH];
			for(int i = 0; i < g_RocketClass_count; i++)
			{
				g_RocketClass[i].GetName(rocketname,MAX_NAME_LENGTH)
				g_class_chance.SetValue(rocketname, kv.GetNum(rocketname,0);
			}
			kv.GoBack();
		}
		kv.GoBack();
	}
	
	if(kv.JumpToKey("multirocketcolor"))
	{
		g_allow_multirocketcolor = view_as<bool>kv.GetNum("AllowMultiRocketColor", 1);
		
		int count = 0;
		kv.GotoFirstSubKey();
		do
		{
			kv.GetString("colorname",g_mrc_name[count],PLATFORM_MAX_PATH,"");
			kv.GetString("color",g_mrc_color[count],32,"255 255 255");
			kv.GetString("trail",g_mrc_trail[count],PLATFORM_MAX_PATH,"");
			g_mrc_applycolor_model[count] = view_as<bool>kv.GetNum("applycolormodel", 1);
			g_mrc_applycolor_trail[count] = view_as<bool>kv.GetNum("applycolortrail", 1);
			count++;
		}
		while (kv.GotoNextKey() && count < MAXMULTICOLORHUD);
	
		kv.GoBack();
	}
	if(kv.JumpToKey("sounds"))
	{
		char key[4], sndFile[PLATFORM_MAX_PATH];
		if(kv.JumpToKey("RoundStart"))
		{
			for(int i=1; i<MAXGENERIC; i++)
			{
				IntToString(i, key, sizeof(key));
				kv.GetString(key, sndFile, sizeof(sndFile),"");
				if(StrEqual(sndFile, ""))
					break;			
				g_SndRoundStart.SetString(key,sndFile);
			}
			kv.GoBack();
		}
		if(kv.JumpToKey("OnDeath"))
		{
			for(int i=1; i<MAXGENERIC; i++)
			{
				IntToString(i, key, sizeof(key));
				kv.GetString(key, sndFile, sizeof(sndFile),"");
				if(StrEqual(sndFile, ""))
					break;			
				g_SndOnDeath.SetString(key,sndFile);
			}
			kv.GoBack();
		}
		if(kv.JumpToKey("OnKill"))
		{
			g_OnKillDelay = kv.GetFloat("delay",5.0);
			for(int i=1; i<MAXGENERIC; i++)
			{
				IntToString(i, key, sizeof(key));
				kv.GetString(key, sndFile, sizeof(sndFile),"");
				if(StrEqual(sndFile, ""))
					break;			
				g_SndOnKill.SetString(key,sndFile);
			}
			kv.GoBack();
		}
		if(kv.JumpToKey("LastAlive"))
		{
			for(int i=1; i<MAXGENERIC; i++)
			{
				IntToString(i, key, sizeof(key));
				kv.GetString(key, sndFile, sizeof(sndFile),"");
				if(StrEqual(sndFile, ""))
					break;			
				g_SndLastAlive.SetString(key,sndFile);
			}
			kv.GoBack();
		}
		kv.GoBack();		
	}
	if(kv.JumpToKey("blockedflamethrowers"))
	{
		char key[4];
		int auxInt;
		for(int i=1; i<MAXGENERIC; i++)
		{
			IntToString(i, key, sizeof(key));
			auxInt = kv.GetNum(key, -1);
			if(auxInt == -1)
				break;
			g_RestrictedWeps.SetValue(key,auxInt);
		}
		
		kv.GoBack();	
	}
	if(kv.JumpToKey("blockcommands"))
	{
		do
		{
			char SectionName[128], CommandName[128];
			int onprep;
			kv.GotoFirstSubKey();
			kv.GetSectionName( SectionName, sizeof(SectionName));
			
			kv.GetString("command", CommandName, sizeof(CommandName));
			onprep = kv.GetNum("OnlyOnPreparation", 1);
			
			if(!StrEqual(CommandName, ""))
			{
				g_CommandToBlock.SetString(SectionName,CommandName);
				g_BlockOnlyOnPreparation.SetValue(SectionName,onprep);
			}
		}
		while(kv.GotoNextKey());
		kv.GoBack();	
	}
	
	
	delete kv;
	
	char mapfile[PLATFORM_MAX_PATH], mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	BuildPath(Path_SM, mapfile, sizeof(mapfile), "data/dodgeball/maps/%s.cfg",mapname);
	
	if(FileExists(mapfile))
	{
		KeyValues kv =  CreateKeyValues("dodgeball");
		if(kv.ImportFromFile(g_mainfile))
		{
			SetFailState("Improper structure for configuration file %s!", g_mainfile);
			return;
		}
		if(kv.JumpToKey("spawner"))
		{
			g_max_rockets = kv.GetNum("MaxRockets", g_max_rockets);
			g_spawn_delay = kv.GetFloat("SpawnDelay", g_spawn_delay);
			if(kv.JumpToKey("chances"))
			{
				g_class_chance.Clear();
				char rocketname[MAX_NAME_LENGTH];
				for(int i = 0; i < g_RocketClass_count; i++)
				{
					g_RocketClass[i].GetName(rocketname,MAX_NAME_LENGTH)
					g_class_chance.SetValue(rocketname, kv.GetNum(rocketname,0);
				}
				kv.GoBack();
			}
			kv.GoBack();
		}
	}
	delete kv;
}

/* OnPrepartionStart()
**
** We setup the cvars again and we freeze the players.
** -------------------------------------------------------------------------- */
public Action OnPrepartionStart(Handle event, const char name[], bool dontBroadcast)
{
	if(!g_isDBmap) return;
	
	g_onPreparation = true;
	
	//We force the cvars values needed every round (to override if any cvar was changed).
	SetupCvars();

	//Players shouldn't move until the round starts
	for(int i = 1; i <= MaxClients; i++)
		if(IsClientInGame(i) && IsPlayerAlive(i))
			SetEntityMoveType(i, MOVETYPE_NONE);	
	//if(g_ShowInfo)
	//	ShowHud(20.0,_,_,_,_);
}

/* OnRoundStart()
**
** We unfreeze every player and we start the rocket timer
** -------------------------------------------------------------------------- */
public Action OnRoundStart(Handle event, const charname[], bool dontBroadcast)
{
	if(!g_isDBmap) return;
	SearchSpawns();
	for(int i = 1; i <= MaxClients; i++)
		if(IsClientInGame(i) && IsPlayerAlive(i))
				SetEntityMoveType(i, MOVETYPE_WALK);
	g_onPreparation = false;
	g_roundActive = true;
	g_canSpawn = false;
	if(GetRandomInt(0,1))
		g_lastSpawned = TEAM_RED
	else
		g_lastSpawned = TEAM_BLUE
	
	FireRocket();

}

/* OnRoundEnd()
**
** Here we destroy the rocket.
** -------------------------------------------------------------------------- */
public Action OnRoundEnd(Handle event, const char name[], bool dontBroadcast)
{
	g_roundActive=false;
	/*if(g_RocketEnt != -1)
	{	
		if (IsValidEntity(g_RocketEnt)) 
			RemoveEdict(g_RocketEnt);
	}*/
}

/* TF2Items_OnGiveNamedItem_Post()
**
** Here we check for the demoshield and the sapper.
** -------------------------------------------------------------------------- */
public TF2Items_OnGiveNamedItem_Post(client, String:classname[], index, level, quality, ent)
{
	if(!g_isDBmap)	return;
	//tf_weapon_builder tf_wearable_demoshield
	if(StrEqual(classname,"tf_weapon_builder", false) || StrEqual(classname,"tf_wearable_demoshield", false))
		CreateTimer(0.1, Timer_RemoveWep, EntIndexToEntRef(ent));  
}

/* Timer_RemoveWep()
**
** We kill the demoshield/sapper
** -------------------------------------------------------------------------- */
public Action Timer_RemoveWep(Handle timer, int ref)
{
	int ent = EntRefToEntIndex(ref);
	if( IsValidEntity(ent) && ent > MaxClients)
		AcceptEntityInput(ent, "Kill");
}  

/* OnPlayerInventory()
**
** Here we strip players weapons (if we have to).
** Also we give special melee weapons (again, if we have to).
** -------------------------------------------------------------------------- */
public Action OnPlayerInventory(Handle event, const char name[], bool dontBroadcast)
{
	if(!g_isDBmap) return;
	
	bool replace_primary = false;
	int client = GetClientOfUserId(GetEventInt(event, "userid"));	
	
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Grenade);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Building);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_PDA);
	
	char classname[64];
	int wep_ent = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if(wep_ent > MaxClients && IsValidEntity(wep_ent))
	{
		int wep_index = GetEntProp(wep_ent, Prop_Send, "m_iItemDefinitionIndex"); 
		if (wep_ent > MaxClients && IsValidEdict(wep_ent) && GetEdictClassname(wep_ent, classname, sizeof(classname)))
		{	
			if (StrEqual(classname, "tf_weapon_flamethrower", false) )
			{
				char key[4];
				int auxIndex;
				for(int i = 1; i <= rwSize; i++)
				{
					IntToString(i,key,sizeof(key));
					if(g_RestrictedWeps.GetValue(key,auxIndex))
						if(wepIndex == auxIndex)
							replace_primary=true;
				}
				if(!replace_primary)
					TF2Attrib_SetByDefIndex(wep_ent, 254, 4.0);
			}
			else
				replace_primary = true;
		}
	}
	if(replace_primary)
	{
		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
		Handle hItem = TF2Items_CreateItem(FORCE_GENERATION | OVERRIDE_CLASSNAME | OVERRIDE_ITEM_DEF | OVERRIDE_ITEM_LEVEL | OVERRIDE_ITEM_QUALITY | OVERRIDE_ATTRIBUTES);
		TF2Items_SetClassname(hItem, "tf_weapon_flamethrower");
		TF2Items_SetItemIndex(hItem, 21);
		TF2Items_SetLevel(hItem, 69);
		TF2Items_SetQuality(hItem, 6);
		TF2Items_SetAttribute(hItem, 0, 254, 4.0); //Can't push other players
		TF2Items_SetNumAttributes(hItem, 1);
		int iWeapon = TF2Items_GiveNamedItem(client, hItem);
		CloseHandle(hItem);
		EquipPlayerWeapon(client, iWeapon);
	}
	
	TF2_SwitchtoSlot(client, TFWeaponSlot_Primary);
	
}

/* OnPlayerSpawn()
**
** Here we set the spy cloak and we move the death player.
** -------------------------------------------------------------------------- */
public Action OnPlayerSpawn(Handle event, const char name[], bool dontBroadcast)
{
	if(!g_isDBmap) return;
	
	int class = GetEntProp(client, Prop_Send, "m_iClass");
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(g_pyro_only)
	{			
		if(!(class == CLASS_PYRO || class == 0 ))
		{
			SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", CLASS_PYRO);			
			SetEntProp(client, Prop_Send, "m_iClass", CLASS_PYRO);
			TF2_RespawnPlayer(client);
		}
	}
	else if(class == CLASS_SPY)
	{
		int cond = GetEntProp(client, Prop_Send, "m_nPlayerCond");
		
		if (cond & PLAYERCOND_SPYCLOAK)
			SetEntProp(client, Prop_Send, "m_nPlayerCond", cond | ~PLAYERCOND_SPYCLOAK);
	}
	if(g_onPreparation)
		SetEntityMoveType(client, MOVETYPE_NONE);	
}

/* SearchSpawns()
**
** Searchs for blue and red rocket spawns
** -------------------------------------------------------------------------- */
public void SearchSpawns()
{
	if(!g_isDBmap) return;
	int iEntity = -1;
	g_RedSpawn = -1;
	g_BlueSpawn = -1;
	while ((iEntity = FindEntityByClassname(iEntity, "info_target")) != -1)
	{
		char strName[32]; 
		GetEntPropString(iEntity, Prop_Data, "m_iName", strName, sizeof(strName));
		if ((StrContains(strName, "rocket_spawn_red") != -1) || (StrContains(strName, "tf_dodgeball_red") != -1))
		{
			g_RedSpawn = iEntity;
		}
		if ((StrContains(strName, "rocket_spawn_blue") != -1) || (StrContains(strName, "tf_dodgeball_blu") != -1))
		{
			g_BlueSpawn = iEntity;
		}
	}
	
	if (g_RedSpawn == -1) SetFailState("No RED spawn points found on this map.");
	if (g_BlueSpawn == -1) SetFailState("No BLU spawn points found on this map.");
	
	
	//ObserverPoint
	/*
	float opPos[3];
	float opAng[3];
	
	int spawner = GetRandomInt(0,1);
	if(spawner == 0)
		spawner = g_RedSpawn;
	else
		spawner = g_BlueSpawn;
	if(IsValidEntity(spawner)&& spawner > MaxClients)
	{
		GetEntPropVector(spawner,Prop_Data,"m_vecOrigin",opPos);
		GetEntPropVector(spawner,Prop_Data, "m_angAbsRotation", opAng);
		g_observer = CreateEntityByName("info_observer_point");
		DispatchKeyValue(g_observer, "Angles", "90 0 0");
		DispatchKeyValue(g_observer, "TeamNum", "0");
		DispatchKeyValue(g_observer, "StartDisabled", "0");
		DispatchSpawn(g_observer);
		AcceptEntityInput(g_observer, "Enable");
		TeleportEntity(g_observer, opPos, opAng, NULL_VECTOR);
	}
	else
	{
		g_observer = -1;
	}
	return;
	*/
}

/* GetRandomRocketClass()
**
** Returns a random rocket based on config's chance
** -------------------------------------------------------------------------- */
public int GetRandomRocketClass()
{
	int classChance[MAXROCKETS], int maxNum = 0;
	char className[MAX_NAME_LENGTH]; 
	
	//Here we get the probability of each rocket class
	for(int i = 0; i < g_RocketClass_count; i++)
	{
		g_RocketClass.GetName(className,MAX_NAME_LENGTH);
		if(!g_class_chance.GetValue(className,classChance[i]))
			classChance[i] = 0;
		else
			maxNum+=classChance[i]
	}
	
	int random = GetRandomInt(1, maxNum);
	int upChance = 0, downChance = 0
	for(int i = 0; i < g_RocketClass_count; i++)
	{
		downChance = upChance;
		upChance = downChance + classChance[i];
		downChance++;
		
		if(random >= downChance && upChance >= random)
			return random;
		
	}
	return 0;
}

/* GetRocketSlot()
**
** Checks if every "slot" of rockets is used
** -------------------------------------------------------------------------- */
public int GetRocketSlot()
{
	for(int i = 0; i < g_max_rockets; i++)
		g_RocketEntity[i].entity == -1;
			return i;
	return -1;
}

/* SearchTarget()
**
** Searchs for a new Target
** -------------------------------------------------------------------------- */
public SearchTarget()
{
	if(!g_isDBmap) return;
	if(g_RocketEnt <= 0) return;
	new rTeam = GetEntProp(g_RocketEnt, Prop_Send, "m_iTeamNum", 1);
	
	//Check by aim
	if(g_AllowAim)
	{
		new rOwner = GetEntPropEnt(g_RocketEnt, Prop_Send, "m_hOwnerEntity");
		if(rOwner != 0)
		{
			new cAimed = GetClientAimTarget(rOwner, true);
			if( cAimed > 0 && cAimed < MaxClients && IsPlayerAlive(cAimed) && GetClientTeam(cAimed) != rTeam )
			{
				g_RocketTarget= cAimed;
				g_RocketAimed = true;
				return;
			}
		}
	}
	g_RocketAimed = false;
	
	//We make a list of possibles players
	new possiblePlayers[MAXPLAYERS+1];
	new possibleNumber = 0;
	for(new i = 1; i <= MaxClients ; i++)
	{
		if(!IsClientConnected(i) || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) == rTeam )
			continue;
		possiblePlayers[possibleNumber] = i;
		possibleNumber++;
	}
	
	//If there weren't any player the could be targeted
	if(possibleNumber == 0)
	{
		g_RocketTarget= -1;
		if(g_roundActive)
			LogError("[DB] Tried to fire a rocket but there weren't any player available.");
		return;
	}
	
	//Random player
	if(!g_TargetClosest)
		g_RocketTarget= possiblePlayers[ GetRandomInt(0,possibleNumber-1)];
	
	//We find the closest player in the valid players vector
	else
	{
		//Some aux variables
		new Float:aux_dist;
		new Float:aux_pos[3];
		//Rocket's position
		new Float:rPos[3];
		GetEntPropVector(g_RocketEnt, Prop_Send, "m_vecOrigin", rPos);
		
		//First player in the list will be the current closest player
		new closest = possiblePlayers[0];
		GetClientAbsOrigin(closest,aux_pos);
		new Float:closest_dist = GetVectorDistance(rPos,aux_pos, true);
		
		
		for(new i = 1; i < possibleNumber; i++)
		{
			//We use the squared option for optimization since we don't need the absolute distance.
			GetClientAbsOrigin(possiblePlayers[i],aux_pos);
			aux_dist = GetVectorDistance(rPos, aux_pos, true);
			if(closest_dist > aux_dist)
			{
				closest = possiblePlayers[i];
				closest_dist = aux_dist;
			}
		}
		g_RocketTarget= closest;
	}
	

}

/* FireRocket()
**
** Timer used to spawn a new rocket.
** -------------------------------------------------------------------------- */
public Action TryFireRocket(Handle timer, int data)
{
	if(g_canSpawn)
		return;
	FireRocket()

}
public Action AllowSpawn(Handle timer, int data)
{
	g_canSpawn = true;
	FireRocket();
}

public void FireRocket()
{
	if(!g_isDBmap || !g_roundActive) return;
	if(!g_canSpawn) return;
	int rIndex = GetRocketSlot();
	if(rIndex == -1) return;
	
	int spawner, rocketTeam;
	if(g_lastSpawned == TEAM_RED)
	{
		rocketTeam == TEAM_BLUE;
		spawner = g_BlueSpawn;
	}
	else
	{
		rocketTeam == TEAM_RED;
		spawner = g_RedSpawn;
	}
	
	new iEntity = CreateEntityByName( "tf_projectile_rocket");
	if (iEntity && IsValidEntity(iEntity))
	{
		int class = GetRandomRocketClass();
		g_RocketEnt[rIndex].entity = iEntity;
		g_RocketEnt[rIndex].class = class;
		g_RocketEnt[rIndex].bounces = 0;
		g_RocketEnt[rIndex].aimed = false;
		g_RocketEnt[rIndex].deflects = 0;
		g_RocketEnt[rIndex].observer = -1;
		g_RocketEnt[rIndex].homing = true;
		
		
		// Fetch spawn point's location and angles.
		float fPosition[3], fAngles[3], fDirection[3], fVelocity[3];
		GetEntPropVector(spawner, Prop_Send, "m_vecOrigin", fPosition);
		GetEntPropVector(spawner, Prop_Send, "m_angRotation", fAngles);
		GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
		g_RocketEnt[rIndex].SetDirection(fDirection);
		//CopyVectors(fDirection, g_RocketDirection);
		
		// Setup rocket entity.
		SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", 0);
		SetEntProp(iEntity,	Prop_Send, "m_bCritical",	 1);
		SetEntProp(iEntity,	Prop_Send, "m_iTeamNum",	 rocketTeam, 1); 
		SetEntProp(iEntity,	Prop_Send, "m_iDeflected",   1);
		
		float aux_mul = g_RocketClass[class].speed;
		fVelocity[0] = fDirection[0]*aux_mul;
		fVelocity[1] = fDirection[1]*aux_mul;
		fVelocity[2] = fDirection[2]*aux_mul;
		TeleportEntity(iEntity, fPosition, fAngles, fVelocity);
		
		SetEntDataFloat(iEntity, FindSendPropOffs("CTFProjectile_Rocket", "m_iDeflected") + 4, g_RocketClass[class].damage, true);
		DispatchSpawn(iEntity);
		
		SDKHook(iEntity, SDKHook_StartTouch, OnStartTouch);
		
		g_RocketEnt[rIndex].target = SearchTarget();
		/*
		EmitSoundToAll(SOUND_SPAWN, iEntity);
		if( g_RocketTarget > 0 && g_RocketTarget <= MaxClients)
			EmitSoundToClient(g_RocketTarget, SOUND_ALERT, _, _, _, _, SOUND_ALERT_VOL);
			*/
		//ShowHud(10.0,aux_mul,g_DeflectCount,0,g_RocketTarget);
		
		//Observer point
		/*if(IsValidEntity(g_observer))
		{
			TeleportEntity(g_observer, fPosition, fAngles, Float:{0.0, 0.0, 0.0});
			SetVariantString("!activator");
			AcceptEntityInput(g_observer, "SetParent", g_RocketEnt);
		}*/
		
		g_lastSpawned = rocketTeam;
		g_canSpawn = false;
		CreateTimer(g_spawn_delay,AllowSpawn);
		
	}
}

public Action:OnStartTouch(entity, other)
{
	if (other > 0 && other <= MaxClients)
		return Plugin_Continue;
	
	// Only allow a rocket to bounce x times.
	if (g_RocketBounces >= g_MaxBounce)
		return Plugin_Continue;
	
	SDKHook(entity, SDKHook_Touch, OnTouch);
	return Plugin_Handled;
}

public Action:OnTouch(entity, other)
{
	decl Float:vOrigin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vOrigin);
	
	decl Float:vAngles[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", vAngles);
	
	decl Float:vVelocity[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vVelocity);
	
	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TEF_ExcludeEntity, entity);
	
	if(!TR_DidHit(trace))
	{
		CloseHandle(trace);
		return Plugin_Continue;
	}
	
	decl Float:vNormal[3];
	TR_GetPlaneNormal(trace, vNormal);
	
	CloseHandle(trace);
	
	new Float:dotProduct = GetVectorDotProduct(vNormal, vVelocity);
	
	ScaleVector(vNormal, dotProduct);
	ScaleVector(vNormal, 2.0);
	
	decl Float:vBounceVec[3];
	SubtractVectors(vVelocity, vNormal, vBounceVec);
	
	decl Float:vNewAngles[3];
	GetVectorAngles(vBounceVec, vNewAngles);
	
	TeleportEntity(entity, NULL_VECTOR, vNewAngles, vBounceVec);

	g_RocketBounces++;
	g_MovEnabled = false;
	CreateTimer(g_Delay,EnableMov);
	SDKUnhook(entity, SDKHook_Touch, OnTouch);
	return Plugin_Handled;
}

public bool:TEF_ExcludeEntity(entity, contentsMask, any:data)
{
	return (entity != data);
}

/* OnGameFrame()
**
** We set the player max speed on every frame, and also we set the spy's cloak on empty.
** Here we also check what to do with the rocket. We checks for deflects and modify the rocket's speed.
** -------------------------------------------------------------------------- */
public OnGameFrame()
{
	
	if(!g_isDBmap) return;
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i))
		{
			SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", PLAYER_SPEED);
			if(TF2_GetPlayerClass(i) == TFClass_Spy)
			{
				SetCloak(i, 1.0);
			}
		}
	}
	//Rocket Management
	if(g_RocketEnt > 0 && g_roundActive) 
	{
		new rOwner = GetEntPropEnt(g_RocketEnt, Prop_Send, "m_hOwnerEntity");
		
		//Check if the target is available
		if(g_RocketTarget < 0 || g_RocketTarget > MaxClients || !IsClientConnected(g_RocketTarget) ||	!IsClientInGame(g_RocketTarget) || !IsPlayerAlive(g_RocketTarget))
		{
			SearchTarget();
		}
		
		//Check deflects
		new rDef  = GetEntProp(g_RocketEnt, Prop_Send, "m_iDeflected") - 1;
		new Float:aux_mul = 0.0;
		if(rDef > g_DeflectCount)
		{
			new Float:fViewAngles[3], Float:fDirection[3];
			GetClientEyeAngles(g_RocketTarget, fViewAngles);
			GetAngleVectors(fViewAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
			CopyVectors(fDirection, g_RocketDirection);
			
			SearchTarget();
			g_DeflectCount++;
			if( g_RocketTarget > 0 && g_RocketTarget <= MaxClients)
			{
				EmitSoundToClient(g_RocketTarget, SOUND_ALERT, _, _, _, _, SOUND_ALERT_VOL);	
				if(g_RocketAimed)
				{
					EmitSoundToClient(g_RocketTarget, SOUND_SPAWN, _, _, _, _, SOUND_ALERT_VOL);	
					if (rOwner > 0 && rOwner <= MaxClients)
						EmitSoundToClient(rOwner, SOUND_SPAWN, _, _, _, _, SOUND_ALERT_VOL);	
						
					SetHudTextParams(-1.0, -1.0, 1.5, ALERT_R, ALERT_G, ALERT_B, 255, 2, 0.28 , 0.1, 0.1);
					ShowSyncHudText(rOwner, g_HudSyncs[hud_SuperShot], "Super Shot!");
				}
			}
			if(g_ShowInfo)
			{
				aux_mul = BASE_SPEED * g_SpeedMul * (1 + g_DeflectInc * rDef);
				ShowHud(10.0,aux_mul,g_DeflectCount,rOwner,g_RocketTarget);
			}
			g_MovEnabled = false;
			CreateTimer(g_Delay,EnableMov);
		}
		//If isn't a deflect then we have to modify the rocket's direction and velocity
		else
		{
			if(g_MovEnabled)
			{
				if(g_RocketTarget > 0 && g_RocketTarget <= MaxClients)
				{
					decl Float:fDirectionToTarget[3]; 
					CalculateDirectionToClient(g_RocketEnt, g_RocketTarget, fDirectionToTarget);
					LerpVectors(g_RocketDirection, fDirectionToTarget, g_RocketDirection, g_Turnrate);
				}
			}
		}
		
		if(g_MovEnabled)
		{
			decl Float:fAngles[3]; GetVectorAngles(g_RocketDirection, fAngles);
			decl Float:fVelocity[3]; CopyVectors(g_RocketDirection, fVelocity);
			
			if(aux_mul == 0.0)
				aux_mul = BASE_SPEED * g_SpeedMul * (1 + g_DeflectInc * rDef);
			if(g_AllowAim && g_RocketAimed)
				aux_mul *= g_AimedSpeedMul;
			fVelocity[0] = g_RocketDirection[0]*aux_mul;
			fVelocity[1] = g_RocketDirection[1]*aux_mul;
			fVelocity[2] = g_RocketDirection[2]*aux_mul;
			SetEntPropVector(g_RocketEnt, Prop_Data, "m_vecAbsVelocity", fVelocity);
			SetEntPropVector(g_RocketEnt, Prop_Send, "m_angRotation", fAngles);
		}
		
	}
}

/* EnableMov()
**
** Timer used re-enable the rocket's movement 
** -------------------------------------------------------------------------- */
public Action:EnableMov(Handle:timer, any:data)
{
	g_MovEnabled = true;
}

/* OnEntityDestroyed()
**
** We check if the rocket got destroyed, and then fire a timer for a new rocket.
** -------------------------------------------------------------------------- */
public OnEntityDestroyed(entity)
{
	if(!g_isDBmap) return;
	if(entity == -1) return;

	if(entity == g_RocketEnt && IsValidEntity(g_RocketEnt))
	{
		g_RocketEnt = -1;
		g_RocketTarget= -1;
		g_RocketAimed = false;
		g_DeflectCount = 0;
		if(g_roundActive)
		{
			CreateTimer(g_spawn_delay, TryFireRocket);
			/*if(g_ShowInfo)
				ShowHud(g_SpawnTime,_,_,_,_);*/

		}
		/*
		if( IsValidEntity(g_observer))
		{
			SetVariantString("");
			AcceptEntityInput(g_observer, "ClearParent");
			
			new Float:opPos[3];
			new Float:opAng[3];
			
			new spawner = GetRandomInt(0,1);
			if(spawner == 0)
				spawner = g_RedSpawn;
			else
				spawner = g_BlueSpawn;
			
			if(IsValidEntity(spawner)&& spawner > MaxClients)
			{
				GetEntPropVector(spawner,Prop_Data,"m_vecOrigin",opPos);
				GetEntPropVector(spawner,Prop_Data, "m_angAbsRotation", opAng);
				TeleportEntity(g_observer, opPos, opAng, NULL_VECTOR);
			}		
		}*/
	}
	
}
/*
stock ShowHud( Float:h_duration=0.1, Float:h_speed=0.0, h_reflects=-1, h_owner=-1, h_target=0)
{

	for(new i = 1; i <= MaxClients; i++)
	{
		if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i))
			continue;
			
		if(g_RocketAimed)
			SetHudTextParams(g_InfoX, g_InfoY, h_duration, ALERT_R, ALERT_G, ALERT_B, 255, 0, 0.0, 0.0, 0.0);
		else
			SetHudTextParams(g_InfoX, g_InfoY, h_duration, DEF_R, DEF_G, DEF_B, 255, 0, 0.0, 0.0, 0.0);
		if(h_speed > 0.0)
			ShowSyncHudText(i, g_HudSyncs[hud_Speed], "Speed: %.1f", h_speed);
		else
			ShowSyncHudText(i, g_HudSyncs[hud_Speed], "Speed: -");

		SetHudTextParams(g_InfoX, g_InfoY + HUD_LINE_SEPARATION, h_duration, DEF_R, DEF_G, DEF_B, 255, 0, 0.0, 0.0, 0.0);
		if(h_reflects > -1)
			ShowSyncHudText(i, g_HudSyncs[hud_Reflects], "Reflects: %d", h_reflects);
		else
			ShowSyncHudText(i, g_HudSyncs[hud_Reflects], "Reflects: -");		

		SetHudTextParams(g_InfoX, g_InfoY + HUD_LINE_SEPARATION*2, h_duration, DEF_R, DEF_G, DEF_B, 255, 0, 0.0, 0.0, 0.0);
		if(h_owner > 0 && h_owner <= MaxClients)
			ShowSyncHudText(i, g_HudSyncs[hud_Owner], "Owner: %N", h_owner);
		else if(h_owner == 0)
			ShowSyncHudText(i, g_HudSyncs[hud_Owner], "Owner: Server");
		else
			ShowSyncHudText(i, g_HudSyncs[hud_Owner], "Owner: -");
			
		SetHudTextParams(g_InfoX, g_InfoY + HUD_LINE_SEPARATION*3, h_duration, DEF_R, DEF_G, DEF_B, 255, 0, 0.0, 0.0, 0.0);
		if(h_target > 0 && h_target <= MaxClients)
			ShowSyncHudText(i, g_HudSyncs[hud_Target], "Target: %N", h_target);
		else
			ShowSyncHudText(i, g_HudSyncs[hud_Target], "Target: -");
	}
}
*/



/* OnConfigsExecuted()
**
** Here we get the default values of the CVars that the plugin is going to modify.
** -------------------------------------------------------------------------- */
public void OnConfigsExecuted()
{
	if(!g_isDBmap) return;
	db_airdash_def = GetConVarInt(db_airdash);
	db_push_def = GetConVarInt(db_push);
	db_burstammo_def = GetConVarInt(db_burstammo);
	SetupCvars();
}

/* SetupCvars()
**
** Modify several values of the CVars that the plugin needs to work properly.
** -------------------------------------------------------------------------- */
public void SetupCvars()
{
	SetConVarInt(db_airdash, 0);
	SetConVarInt(db_push, 0);
	SetConVarInt(db_burstammo,0);
}

/* ResetCvars()
**
** Reset the values of the CVars that the plugin used to their default values.
** -------------------------------------------------------------------------- */
public void ResetCvars()
{
	SetConVarInt(db_airdash, db_airdash_def);
	SetConVarInt(db_push, db_push_def);
	SetConVarInt(db_burstammo, db_burstammo_def);
}

/* OnPlayerRunCmd()
**
** Block flamethrower's Mouse1 attack.
** -------------------------------------------------------------------------- */
public Action OnPlayerRunCmd(iClient, &iButtons, &iImpulse, Float:fVelocity[3], Float:fAngles[3], &iWeapon)
{
	if(!g_isDBmap) return Plugin_Continue;
	iButtons &= ~IN_ATTACK;
	return Plugin_Continue;
}

/* Command_Block()
**
** Blocks a command
** -------------------------------------------------------------------------- */
public Action Command_Block(client, const String:command[], argc)
{
	if(g_isDBmap)
		return Plugin_Stop;
	return Plugin_Continue;
}

/* TF2_SwitchtoSlot()
**
** Changes the client's slot to the desired one.
** -------------------------------------------------------------------------- */
stock void TF2_SwitchtoSlot(int client, int slot)
{
	if (slot >= 0 && slot <= 5 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		char classname[64];
		int wep = GetPlayerWeaponSlot(client, slot);
		if (wep > MaxClients && IsValidEdict(wep) && GetEdictClassname(wep, classname, sizeof(classname)))
		{
			FakeClientCommandEx(client, "use %s", classname);
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", wep);
		}
	}
}

/* SetCloak()
**
** Function used to set the spy's cloak meter.
** -------------------------------------------------------------------------- */
stock void SetCloak(int client, float value)
{
	SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", value);
}

/* CopyVectors()
**
** Copies the contents from a vector to another.
** -------------------------------------------------------------------------- */
stock void CopyVectors(float fFrom[3], float fTo[3])
{
	fTo[0] = fFrom[0];
	fTo[1] = fFrom[1];
	fTo[2] = fFrom[2];
}

/* LerpVectors()
**
** Calculates the linear interpolation of the two given vectors and stores
** it on the third one.
** -------------------------------------------------------------------------- */
stock void LerpVectors(float fA[3], float fB[3], float fC[3], float t)
{
	if (t < 0.0) t = 0.0;
	if (t > 1.0) t = 1.0;
	
	fC[0] = fA[0] + (fB[0] - fA[0]) * t;
	fC[1] = fA[1] + (fB[1] - fA[1]) * t;
	fC[2] = fA[2] + (fB[2] - fA[2]) * t;
}

/* CalculateDirectionToClient()
**
** As the name indicates, calculates the orientation for the rocket to move
** towards the specified client.
** -------------------------------------------------------------------------- */
stock void CalculateDirectionToClient(int iEntity, int iClient, float fOut[3])
{
	if(iClient < 0 || iClient > MaxClients)
		return;
	float fRocketPosition[3]; 
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fRocketPosition);
	GetClientEyePosition(iClient, fOut);
	MakeVectorFromPoints(fRocketPosition, fOut, fOut);
	NormalizeVector(fOut, fOut);
}