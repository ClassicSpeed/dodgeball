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
//#pragma newdecls required

#include <dodgeball>

// ---- Defines ----------------------------------------------------------------
#define DB_VERSION "0.2.0"
#define PLAYERCOND_SPYCLOAK (1<<4)
#define MAXGENERIC 25
#define MAXMULTICOLORHUD 5
#define MAXHUDNUMBER 6
#define TEAM_RED 2
#define TEAM_BLUE 3
#define CLASS_PYRO 7
#define CLASS_SPY 8

#define SOUND_ALERT_VOL	0.8
#define HUD_LINE_SEPARATION 0.04

//Nuke explosion
#define PARTICLE_NUKE_1         "fireSmokeExplosion"
#define PARTICLE_NUKE_2         "fireSmokeExplosion1"
#define PARTICLE_NUKE_3         "fireSmokeExplosion2"
#define PARTICLE_NUKE_4         "fireSmokeExplosion3"
#define PARTICLE_NUKE_5         "fireSmokeExplosion4"
#define PARTICLE_NUKE_COLLUMN   "fireSmoke_collumnP"
#define PARTICLE_NUKE_1_ANGLES  Float:{270.0, 0.0, 0.0}
#define PARTICLE_NUKE_2_ANGLES  PARTICLE_NUKE_1_ANGLES
#define PARTICLE_NUKE_3_ANGLES  PARTICLE_NUKE_1_ANGLES
#define PARTICLE_NUKE_4_ANGLES  PARTICLE_NUKE_1_ANGLES
#define PARTICLE_NUKE_5_ANGLES  PARTICLE_NUKE_1_ANGLES
#define PARTICLE_NUKE_COLLUMN_ANGLES  PARTICLE_NUKE_1_ANGLES

enum
{
	rsnd_spawn,
	rsnd_alert,
	rsnd_bludeflect,
	rsnd_reddeflect,
	rsnd_beep,
	rsnd_bounce,
	rsnd_aimed,
	rsnd_exp
}

// ---- Variables --------------------------------------------------------------
bool g_isDBmap = false;
bool g_onPreparation = false;
bool g_roundActive = false;
bool g_canSpawn = false;
bool g_canEmitKillSound = true;
int g_lastSpawned;

int g_BlueSpawn = -1;
int g_RedSpawn = -1;
int g_ClientAimed[MAXPLAYERS+1];
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
bool g_mrc_use_light[MAXMULTICOLORHUD];

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
	g_SndRoundStart = CreateTrie();
	g_SndOnDeath = CreateTrie();
	g_SndOnKill = CreateTrie();
	g_SndLastAlive = CreateTrie();
	g_RestrictedWeps = CreateTrie();
	g_CommandToBlock = CreateTrie();
	g_BlockOnlyOnPreparation = CreateTrie();
	g_class_chance = CreateTrie();
	
	//Server's Cvars
	db_airdash = FindConVar("tf_scout_air_dash_count");
	db_push = FindConVar("tf_avoidteammates_pushaway");
	db_burstammo = FindConVar("tf_flamethrower_burstammo");

	//HUD
	for(int i = 0; i < MAXHUDNUMBER; i++)
		g_HudSyncs[i]= CreateHudSynchronizer();

	//Rocket classes
	for(int i = 0; i < MAXROCKETCLASS; ++i)
		g_RocketClass[i] = RocketClass(i);
	//Rocket entities
	for(int i = 0; i < MAXROCKETS; ++i)
		g_RocketEnt[i] = RocketEnt(i);
		
	//Hooks
	HookEvent("teamplay_round_start", OnPrepartionStart);
	HookEvent("arena_round_start", OnRoundStart); 
	HookEvent("post_inventory_application", OnPlayerInventory);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	HookEvent("teamplay_round_win", OnRoundEnd);
	HookEvent("teamplay_round_stalemate", OnRoundEnd);
	
	//Constant file paths
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
		
		PrecacheFiles();
		ProcessListeners(false);
		
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
public void OnMapEnd()
{
	g_roundActive = false;
	for(int i = 0; i < MAXROCKETS; i++)
	{
		g_RocketEnt[i].entity = INVALID_ENT_REFERENCE;
	}
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
	if(!kv.ImportFromFile(g_rocketclasses))
	{
		delete kv;
		SetFailState("Improper structure for configuration file %s!", g_rocketclasses);
		return;
	}
	if(!kv.JumpToKey("default"))
	{
		delete kv;
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
	defClass.targetclosest = !!kv.GetNum("TargetClosest",0);
	defClass.allowaimed = !!kv.GetNum("AllowAimed",0);
	defClass.aimedspeed = kv.GetFloat("AimedSpeed",2500.0);
	//Bounce
	defClass.maxbounce = kv.GetNum("MaxBounce",10);
	defClass.bouncedelay = kv.GetFloat("BouceDelay",0.1);
	
	//Sounds

	//Spawn
	defClass.snd_spawn_use = !!kv.GetNum("PlaySpawnSound",1);
	kv.GetString("SpawnSound",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetSndSpawn(auxPath);
	//Alert
	defClass.snd_alert_use = !!kv.GetNum("PlayAlertSound",1);
	kv.GetString("AlertSound",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetSndAlert(auxPath);
	//Deflect
	defClass.snd_deflect_use = !!kv.GetNum("PlayDeflectSound",1);
	kv.GetString("RedDeflectSound",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetSndDeflectRed(auxPath);
	kv.GetString("BlueDeflectSound",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetSndDeflectBlue(auxPath);
	//Beep
	defClass.snd_beep_use = !!kv.GetNum("PlayBeepSound",1);
	kv.GetString("BeepSound",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetSndBeep(auxPath);
	defClass.snd_beep_delay = kv.GetFloat("BeepInterval",1.0);
	//Bounce
	defClass.snd_bounce_use = !!kv.GetNum("PlayBounceSound",1);
	kv.GetString("BounceSound",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetSndBounce(auxPath);
	//Aimed
	defClass.snd_aimed_use = !!kv.GetNum("PlayAimedSound",1);
	kv.GetString("AimedSound",auxPath,PLATFORM_MAX_PATH,"");
	defClass.SetSndAimed(auxPath);
		
	//Explosion
	if(kv.JumpToKey("explosion"))
	{
		defClass.exp_use = !!kv.GetNum("CreateBigExplosion",0);
		defClass.exp_damage = kv.GetFloat("Damage",200.0);
		defClass.exp_push = kv.GetFloat("PushStrength",1000.0);
		defClass.exp_radius = kv.GetFloat("Radius",1000.0);
		defClass.exp_fallof = kv.GetFloat("FallOfRadius",600.0);
		kv.GetString("Sound",auxPath,PLATFORM_MAX_PATH,"");
		defClass.SetExpSound(auxPath);
		kv.GoBack();
	}
	else
		defClass.exp_use = false;
		
	kv.GoBack();
	
	//Here we read all the classes
	if(!kv.JumpToKey("Classes"))
	{
		delete kv;
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
		g_RocketClass[count].targetclosest = !!kv.GetNum("TargetClosest",defClass.targetclosest);
		g_RocketClass[count].allowaimed = !!kv.GetNum("AllowAimed",defClass.allowaimed);
		g_RocketClass[count].aimedspeed = kv.GetFloat("AimedSpeed",defClass.aimedspeed);
		//Bounce
		g_RocketClass[count].maxbounce = kv.GetNum("MaxBounce",defClass.maxbounce);
		g_RocketClass[count].bouncedelay = kv.GetFloat("BouceDelay",defClass.bouncedelay);
		
		//Sounds
		
		//Spawn
		g_RocketClass[count].snd_spawn_use = !!kv.GetNum("PlaySpawnSound",defClass.snd_spawn_use);
		defClass.GetSndSpawn(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("SpawnSound",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetSndSpawn(auxPath);
		//Alert
		g_RocketClass[count].snd_alert_use = !!kv.GetNum("PlayAlertSound",defClass.snd_alert_use);
		defClass.GetSndAlert(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("AlertSound",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetSndAlert(auxPath);
		//Deflect
		g_RocketClass[count].snd_deflect_use = !!kv.GetNum("PlayDeflectSound",defClass.snd_deflect_use);
		defClass.GetSndDeflectRed(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("RedDeflectSound",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetSndDeflectRed(auxPath);
		defClass.GetSndDeflectBlue(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("BlueDeflectSound",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetSndDeflectBlue(auxPath);
		//Beep
		g_RocketClass[count].snd_beep_use = !!kv.GetNum("PlayBeepSound",defClass.snd_beep_use);
		defClass.GetSndBeep(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("BeepSound",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetSndBeep(auxPath);
		g_RocketClass[count].snd_beep_delay = kv.GetFloat("BeepInterval",defClass.snd_beep_delay);
		//Bounce
		g_RocketClass[count].snd_bounce_use = !!kv.GetNum("PlayBounceSound",defClass.snd_aimed_use);
		defClass.GetSndBounce(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("BounceSound",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetSndBounce(auxPath);
		//Aimed
		g_RocketClass[count].snd_aimed_use = !!kv.GetNum("PlayAimedSound",defClass.snd_aimed_use);
		defClass.GetSndAimed(auxPath,PLATFORM_MAX_PATH);
		kv.GetString("AimedSound",auxPath,PLATFORM_MAX_PATH,auxPath);
		g_RocketClass[count].SetSndAimed(auxPath);
		
		//Explosion
		if(kv.JumpToKey("explosion"))
		{
			g_RocketClass[count].exp_use = !!kv.GetNum("CreateBigExplosion",defClass.exp_use);
			g_RocketClass[count].exp_damage = kv.GetFloat("Damage",defClass.exp_damage);
			g_RocketClass[count].exp_push = kv.GetFloat("PushStrength",defClass.exp_push);
			g_RocketClass[count].exp_radius = kv.GetFloat("Radius",defClass.exp_radius);
			g_RocketClass[count].exp_fallof = kv.GetFloat("FallOfRadius",defClass.exp_fallof);
			defClass.GetExpSound(auxPath,PLATFORM_MAX_PATH);
			kv.GetString("Sound",auxPath,PLATFORM_MAX_PATH,auxPath);
			g_RocketClass[count].SetExpSound(auxPath);
			
			kv.GoBack();
		}
		else
			g_RocketClass[count].exp_use = false;
		count++;
	}
	while (kv.GotoNextKey() && count < MAXROCKETCLASS);
	delete kv;
	g_RocketClass_count = count;
		
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
	if(!kv.ImportFromFile(g_mainfile))
	{
		delete kv;
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
	g_pyro_only = !!kv.GetNum("OnlyPyro",0);
	g_hud_show = !!kv.GetNum("ShowHud",0);
	g_hud_x = kv.GetFloat("Xpos", 0.03);
	g_hud_y = kv.GetFloat("Ypos", 0.21);
	kv.GetString("color",g_hud_color,32,"63 255 127");
	kv.GetString("supershottext",g_hud_aimed_text,PLATFORM_MAX_PATH,"Super Shot!");
	kv.GetString("supershotcolor",g_hud_aimed_color,32,"63 255 127");
	
	if(kv.JumpToKey("spawner"))
	{
		g_max_rockets = kv.GetNum("MaxRockets", 2);
		g_spawn_delay = kv.GetFloat("SpawnDelay",2.0);
		if(kv.JumpToKey("chances"))
		{
			char rocketname[MAX_NAME_LENGTH];
			for(int i = 0; i < g_RocketClass_count; i++)
			{
				g_RocketClass[i].GetName(rocketname,MAX_NAME_LENGTH);
				g_class_chance.SetValue(rocketname, kv.GetNum(rocketname,0));
			}
			kv.GoBack();
		}
		kv.GoBack();
	}
	
	if(kv.JumpToKey("multirocketcolor"))
	{
		g_allow_multirocketcolor = !!kv.GetNum("AllowMultiRocketColor", 1);
		
		int count = 0;
		kv.GotoFirstSubKey();
		do
		{
			kv.GetString("colorname",g_mrc_name[count],PLATFORM_MAX_PATH,"");
			kv.GetString("color",g_mrc_color[count],32,"255 255 255");
			kv.GetString("trail",g_mrc_trail[count],PLATFORM_MAX_PATH,"");
			g_mrc_applycolor_model[count] = !!kv.GetNum("applycolormodel", 1);
			g_mrc_applycolor_trail[count] = !!kv.GetNum("applycolortrail", 1);
			g_mrc_use_light[count] = !!kv.GetNum("uselight", 1);
			count++;
		}
		while (kv.GotoNextKey() && count < MAXMULTICOLORHUD);
	
		kv.GoBack();
	}
	
	kv.Rewind();
	if(kv.JumpToKey("sounds"))
	{
		//LogMessage("Parsin' sounds.");
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
				//LogMessage("Parsin' sounds on start (%s)",key);
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
	kv.Rewind();
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
	kv.Rewind();
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
		kv =  CreateKeyValues("dodgeball");
		if(!kv.ImportFromFile(g_mainfile))
		{
			LogMessage("Improper structure for configuration file %s! Since it's a map file it'll be ignored.", g_mainfile);
			delete kv;
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
					g_RocketClass[i].GetName(rocketname,MAX_NAME_LENGTH);
					g_class_chance.SetValue(rocketname, kv.GetNum(rocketname,0));
				}
				kv.GoBack();
			}
			kv.GoBack();
		}
	}
	delete kv;
}

/* PrecacheFiles()
**
** We precache and add to the download table every sound/model/material file found on the config file.
** -------------------------------------------------------------------------- */
public void PrecacheFiles()
{
	PrecacheSoundFromTrie(g_SndRoundStart);
	PrecacheSoundFromTrie(g_SndOnDeath);
	PrecacheSoundFromTrie(g_SndOnKill);
	PrecacheSoundFromTrie(g_SndLastAlive);
	for( int i = 0; i < MAXMULTICOLORHUD; i++)
		if(!StrEqual(g_mrc_trail[i],""))
			PrecacheTrail(g_mrc_trail[i]);
	
	
	PrecacheParticle(PARTICLE_NUKE_1);
	PrecacheParticle(PARTICLE_NUKE_2);
	PrecacheParticle(PARTICLE_NUKE_3);
	PrecacheParticle(PARTICLE_NUKE_4);
	PrecacheParticle(PARTICLE_NUKE_5);
	PrecacheParticle(PARTICLE_NUKE_COLLUMN);
			
	char auxPath[PLATFORM_MAX_PATH];
	for( int i = 0; i < g_RocketClass_count; i++)
	{
		g_RocketClass[i].GetTrail(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))
			PrecacheTrail(auxPath);
		
		g_RocketClass[i].GetModel(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))
			PrecacheModelEx(auxPath,true,true);
			
		g_RocketClass[i].GetSndSpawn(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
		g_RocketClass[i].GetSndAlert(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
		g_RocketClass[i].GetSndDeflectBlue(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
		g_RocketClass[i].GetSndDeflectRed(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
		g_RocketClass[i].GetSndBeep(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
		g_RocketClass[i].GetSndAimed(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
		g_RocketClass[i].GetSndBounce(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
		g_RocketClass[i].GetExpSound(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))	
			PrecacheSoundFile(auxPath);
	}
	
		
	
}

/* PrecacheSoundFromTrie()
**
** We precache every sound from a trie.
** -------------------------------------------------------------------------- */
PrecacheSoundFromTrie(StringMap sndTrie)
{
	char soundString[PLATFORM_MAX_PATH], downloadString[PLATFORM_MAX_PATH], key[4];
	for(int i = 1; i <= sndTrie.Size; i++)
	{
		IntToString(i,key,sizeof(key));
		if(GetTrieString(sndTrie,key,soundString, sizeof(soundString)))
		{
			if(PrecacheSound(soundString))
			{
				Format(downloadString, sizeof(downloadString), "sound/%s", soundString);
				AddFileToDownloadsTable(downloadString);
			}
		}
	}
}

/* PrecacheSoundFile()
**
** We precache a sound file.
** -------------------------------------------------------------------------- */
PrecacheSoundFile(char[] strFileName)
{
	if(PrecacheSound(strFileName))
	{
		char downloadString[PLATFORM_MAX_PATH];
		Format(downloadString, sizeof(downloadString), "sound/%s", strFileName);
		AddFileToDownloadsTable(downloadString);
	}
}

/* PrecacheSoundFile()
**
** We precache trail file.
** -------------------------------------------------------------------------- */
PrecacheTrail(char[] strFileName)
{
	char downloadString[PLATFORM_MAX_PATH];
	FormatEx(downloadString, sizeof(downloadString), "%s.vmt", strFileName);
	PrecacheGeneric(downloadString, true);
	AddFileToDownloadsTable(downloadString);
	FormatEx(downloadString, sizeof(downloadString), "%s.vtf", strFileName);
	PrecacheGeneric(downloadString, true);
	AddFileToDownloadsTable(downloadString);
}

/* PrecacheModelEx()
**
** Precaches a models and adds it to the download table.
** -------------------------------------------------------------------------- */
stock PrecacheModelEx(String:strFileName[], bool:bPreload=false, bool:bAddToDownloadTable=false)
{
	PrecacheModel(strFileName, bPreload);
	if (bAddToDownloadTable)
	{
		char strDepFileName[PLATFORM_MAX_PATH];
		Format(strDepFileName, sizeof(strDepFileName), "%s.res", strFileName);
		
		if (FileExists(strDepFileName))
		{
			// Open stream, if possible
			Handle hStream = OpenFile(strDepFileName, "r");
			if (hStream == INVALID_HANDLE) {LogMessage("Error, can't read file containing model dependencies."); return; }
			
			while(!IsEndOfFile(hStream))
			{
				char strBuffer[PLATFORM_MAX_PATH];
				ReadFileLine(hStream, strBuffer, sizeof(strBuffer));
				CleanString(strBuffer);
				
				// If file exists...
				if (FileExists(strBuffer, true))
				{
					// Precache depending on type, and add to download table
					if (StrContains(strBuffer, ".vmt", false) != -1)	  PrecacheDecal(strBuffer, true);
					else if (StrContains(strBuffer, ".mdl", false) != -1) PrecacheModel(strBuffer, true);
					else if (StrContains(strBuffer, ".pcf", false) != -1) PrecacheGeneric(strBuffer, true);
					AddFileToDownloadsTable(strBuffer);
				}
			}
			
			// Close file
			CloseHandle(hStream);
		}
	}
}

/* ProcessListeners()
**
** Here we add the listeners to block the commands defined on the config file.
** -------------------------------------------------------------------------- */
public void ProcessListeners(bool removeListerners)
{
	
	char command[PLATFORM_MAX_PATH], key[4];
	int PreparationOnly;
	for(int i = 1; i <= g_CommandToBlock.Size; i++)
	{
		IntToString(i,key,sizeof(key));
		if(GetTrieString(g_CommandToBlock,key,command, sizeof(command)))
		{
			if(StrEqual(command, ""))
					break;		
					
			GetTrieValue(g_BlockOnlyOnPreparation,key,PreparationOnly);
			if(removeListerners)
			{
				if(PreparationOnly == 1)
					RemoveCommandListener(Command_Block_PreparationOnly,command);
				else
					RemoveCommandListener(Command_Block,command);
			}
			else
			{
				if(PreparationOnly == 1)
					AddCommandListener(Command_Block_PreparationOnly,command);
				else
					AddCommandListener(Command_Block,command);
			}
			
			
		}
	}
}

/* OnPrepartionStart()
**
** We setup the cvars again and we freeze the players.
** -------------------------------------------------------------------------- */
public Action OnPrepartionStart(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_isDBmap) return;
	
	g_onPreparation = true;
	
	//We force the cvars values needed every round (to override if any cvar was changed).
	SetupCvars();

	//Players shouldn't move until the round starts
	for(int i = 1; i <= MaxClients; i++)
		if(IsValidAliveClient(i))
			SetEntityMoveType(i, MOVETYPE_NONE);	
			
	EmitRandomSound(g_SndRoundStart);
	//if(g_ShowInfo)
	//	ShowHud(20.0,_,_,_,_);
}

/* OnRoundStart()
**
** We unfreeze every player and we start the rocket timer
** -------------------------------------------------------------------------- */
public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_isDBmap) return;
	SearchSpawns();
	RenderHud();
	for(int i = 1; i <= MaxClients; i++)
		if(IsValidAliveClient(i))
		{
			SetEntityMoveType(i, MOVETYPE_WALK);
			g_ClientAimed[i] = 0;
		}
	g_onPreparation = false;
	g_roundActive = true;
	g_canSpawn = true;
	g_lastSpawned = GetRandomInt(2,3);
	FireRocket();

}

/* OnRoundEnd()
**
** Here we destroy the rocket.
** -------------------------------------------------------------------------- */
public Action OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_isDBmap) return;
	g_roundActive=false;
	for(int i = 0; i < g_max_rockets; i++)
	{
		int index = EntRefToEntIndex(g_RocketEnt[i].entity);
		if (index != INVALID_ENT_REFERENCE)
		{
			int dissolver = CreateEntityByName("env_entity_dissolver");

			if (dissolver == -1)  return;
			
			DispatchKeyValue(dissolver, "dissolvetype", "0");
			DispatchKeyValue(dissolver, "magnitude", "1");
			DispatchKeyValue(dissolver, "target", "!activator");

			AcceptEntityInput(dissolver, "Dissolve", index);
			AcceptEntityInput(dissolver, "Kill");
		}
	}
	ClearHud();
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
public Action OnPlayerInventory(Handle event, const char[] name, bool dontBroadcast)
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
				for(int i = 1; i <= g_RestrictedWeps.Size; i++)
				{
					IntToString(i,key,sizeof(key));
					if(g_RestrictedWeps.GetValue(key,auxIndex))
						if(wep_index == auxIndex)
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
public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_isDBmap) return;
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int class = GetEntProp(client, Prop_Send, "m_iClass");
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


/* OnPlayerDeath()
**
** Here we reproduce sounds if needed and activate the glow effect if needed
** -------------------------------------------------------------------------- */
public Action:OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!g_isDBmap) return;
	if(g_onPreparation) return;
	

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	EmitRandomSound(g_SndOnDeath,client);
	int killer = GetClientOfUserId(GetEventInt(event, "attacker"));
	if(g_canEmitKillSound && client != killer && killer > 0)
	{
		EmitRandomSound(g_SndOnKill,killer);
		g_canEmitKillSound = false;
		CreateTimer(g_OnKillDelay, ReenableKillSound);
	}
	
	int aliveTeammates = GetAlivePlayersCount(GetClientTeam(client),client);
	if(aliveTeammates == 1)
		EmitRandomSound(g_SndLastAlive,GetLastPlayer(GetClientTeam(client),client));
	
	int iInflictor = GetEventInt(event, "inflictor_entindex");
	int rIndex = GetRocketIndex(iInflictor);
	if(rIndex >= 0)
	{	int class = g_RocketEnt[rIndex].class;
		if(g_RocketClass[class].exp_use)
			CreateExplosion(rIndex);
	}
	
	

}

public Action ReenableKillSound(Handle timer, int data)
{
	g_canEmitKillSound = true;
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
			g_RedSpawn = EntIndexToEntRef(iEntity);
		if ((StrContains(strName, "rocket_spawn_blue") != -1) || (StrContains(strName, "tf_dodgeball_blu") != -1))
			g_BlueSpawn = EntIndexToEntRef(iEntity);
	}
	
	if (g_RedSpawn == INVALID_ENT_REFERENCE)
		SetFailState("No RED spawn points found on this map.");
	if (g_BlueSpawn == INVALID_ENT_REFERENCE)
		SetFailState("No BLU spawn points found on this map.");
	
	
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
	int classChance[MAXROCKETS];
	char className[MAX_NAME_LENGTH]; 
	
	//Here we get the probability of each rocket class
	int maxNum = 0;
	for(int i = 0; i < g_RocketClass_count; i++)
	{
		g_RocketClass[i].GetName(className,MAX_NAME_LENGTH);
		if(!g_class_chance.GetValue(className,classChance[i]))
			classChance[i] = 0;
		else
			maxNum+=classChance[i];
	}
	
	int random = GetRandomInt(1, maxNum);
	
	int upChance = 0, downChance = 1;
	for(int i = 0; i < g_RocketClass_count; i++)
	{
		downChance = upChance + 1;
		upChance = downChance + classChance[i] -1;
		if(random >= downChance && upChance >= random)
			return i;
		
	}
	return 0;
}

/* GetRocketSlot()
**
** Checks if every "slot" of rockets is used
** -------------------------------------------------------------------------- */
public int GetRocketSlot()
{
	int index;
	for(int i = 0; i < g_max_rockets; i++)
	{
		index = EntRefToEntIndex(g_RocketEnt[i].entity);
		if (index == INVALID_ENT_REFERENCE)
			return i;
	}
	return -1;
}

/* GetRocketIndex()
**
** Gets the rocket index from a entity reference
** -------------------------------------------------------------------------- */
public int GetRocketIndex(int entity)
{
	for(int i = 0; i < g_max_rockets; i++)
		if(g_RocketEnt[i].entity == entity)
			return i;
	return -1;
}

/* SearchTarget()
**
** Searchs for a new Target
** -------------------------------------------------------------------------- */
public int SearchTarget(int rIndex)
{
	if(!g_isDBmap) return -1;
	int index = EntRefToEntIndex(g_RocketEnt[rIndex].entity);
	if (index == INVALID_ENT_REFERENCE)
		return -1;
	if(!g_roundActive) return -1;
	int rTeam = GetEntProp(index, Prop_Send, "m_iTeamNum", 1);
	int class = g_RocketEnt[rIndex].class;
	//Check by aim
	if(g_RocketClass[class].allowaimed)
	{
		int rOwner = GetEntPropEnt(index, Prop_Send, "m_hOwnerEntity");
		if(rOwner != 0)
		{
			int cAimed = GetClientAimTarget(rOwner, true);
			if( IsValidAliveClient(cAimed) && GetClientTeam(cAimed) != rTeam )
			{
				g_RocketEnt[rIndex].aimed = true;
				return cAimed;
			}
		}
	}
	g_RocketEnt[rIndex].aimed = false;
	
	//We make a list of possibles players
	int possiblePlayers[MAXPLAYERS+1];
	int possibleNumber = 0;
	for(int i = 1; i <= MaxClients ; i++)
	{
		if(!IsValidAliveClient(i) || GetClientTeam(i) == rTeam || g_ClientAimed[i] > 0)
			continue;
		possiblePlayers[possibleNumber] = i;
		possibleNumber++;
	}
	
	//If there weren't any player the could be targeted the we try even with already aimed clients.
	if(possibleNumber == 0)
	{
		for(int i = 1; i <= MaxClients ; i++)
		{
			if(!IsValidAliveClient(i) || GetClientTeam(i) == rTeam)
				continue;
			possiblePlayers[possibleNumber] = i;
			possibleNumber++;
		}
		if(possibleNumber == 0)
			return -1;
	}
	
	//Random player
	if(!g_RocketClass[class].targetclosest)
		return possiblePlayers[ GetRandomInt(0,possibleNumber-1)];
	
	//We find the closest player in the valid players vector
	else
	{
		//Some aux variables
		float aux_dist;
		float aux_pos[3];
		//Rocket's position
		float rPos[3];
		GetEntPropVector(index, Prop_Send, "m_vecOrigin", rPos);
		
		//First player in the list will be the current closest player
		int closest = possiblePlayers[0];
		GetClientAbsOrigin(closest,aux_pos);
		float closest_dist = GetVectorDistance(rPos,aux_pos, true);
		
		
		for(int i = 1; i < possibleNumber; i++)
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
		return closest;
	}
	

}

/* TryFireRocket()
**
** Timer used to try fire a new rocket.
** -------------------------------------------------------------------------- */
public Action TryFireRocket(Handle timer, int data)
{
	FireRocket();

}
/* AllowSpawn()
**
** Timer used to allow the new rocket and fire it.
** -------------------------------------------------------------------------- */
public Action AllowSpawn(Handle timer, int data)
{
	g_canSpawn = true;
	FireRocket();
}
/* FireRocket()
**
** Function used to spawn the actual rocket.
** This will check if there are available slots and won't fire if a rocket was fired recently.
** -------------------------------------------------------------------------- */
public void FireRocket()
{
	if(!g_isDBmap || !g_roundActive) return;
	if(!g_canSpawn) return;
	if(!g_roundActive) return;
	int rIndex = GetRocketSlot();
	LogMessage("Going to spawn the rocket slot %d).",rIndex);
	if(rIndex == -1) return;
	
	int spawner, rocketTeam;
	if(g_lastSpawned == TEAM_RED)
	{
		rocketTeam = TEAM_BLUE;
		spawner = g_BlueSpawn;
	}
	else
	{
		rocketTeam = TEAM_RED;
		spawner = g_RedSpawn;
	}
	
	int iEntity = CreateEntityByName( "tf_projectile_rocket");
	if(iEntity && IsValidEntity(iEntity))
	{
		int class = GetRandomRocketClass();
		g_RocketEnt[rIndex].entity = EntIndexToEntRef(iEntity);
		g_RocketEnt[rIndex].class = class;
		g_RocketEnt[rIndex].bounces = 0;
		g_RocketEnt[rIndex].aimed = false;
		g_RocketEnt[rIndex].deflects = 0;
		g_RocketEnt[rIndex].observer = -1;
		g_RocketEnt[rIndex].homing = true;
		g_RocketEnt[rIndex].beeptimer = null;
		
		
		// Fetch spawn point's location and angles.
		float fPosition[3], fAngles[3], fDirection[3], fVelocity[3];
		GetEntPropVector(spawner, Prop_Send, "m_vecOrigin", fPosition);
		GetEntPropVector(spawner, Prop_Send, "m_angRotation", fAngles);
		GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
		g_RocketEnt[rIndex].SetDirection(fDirection);
		//CopyVectors(fDirection, g_RocketDirection);
		
		// Setup rocket entity.
		SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", 0);
		//SetEntProp(iEntity,	Prop_Send, "m_bCritical",	 1);
		SetEntProp(iEntity,	Prop_Send, "m_iTeamNum",	 rocketTeam, 1); 
		SetEntProp(iEntity,	Prop_Send, "m_iDeflected",   1);
		
		float aux_mul = g_RocketClass[class].speed;
		g_RocketEnt[rIndex].speed = aux_mul;
		fVelocity[0] = fDirection[0]*aux_mul;
		fVelocity[1] = fDirection[1]*aux_mul;
		fVelocity[2] = fDirection[2]*aux_mul;
		TeleportEntity(iEntity, fPosition, fAngles, fVelocity);
		
		SetEntDataFloat(iEntity, FindSendPropOffs("CTFProjectile_Rocket", "m_iDeflected") + 4, g_RocketClass[class].damage, true);
		DispatchSpawn(iEntity);
		
		char auxPath[PLATFORM_MAX_PATH];
		g_RocketClass[class].GetModel(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))
			SetEntityModel(iEntity, auxPath);
		
		if(g_RocketClass[class].size > 0.0)
			SetEntPropFloat(iEntity, Prop_Send, "m_flModelScale", g_RocketClass[class].size);
			
		if(useMultiColor())
		{
			if(!StrEqual(g_mrc_trail[rIndex],""))
				AttachTrail(rIndex);
			if(g_mrc_applycolor_model[rIndex])
				DispatchKeyValue(iEntity, "rendercolor", g_mrc_color[rIndex]);
			if(g_mrc_use_light[rIndex])
				AttachLight(rIndex);
		}
		else 
		{
			g_RocketClass[class].GetTrail(auxPath,PLATFORM_MAX_PATH);
			if(!StrEqual(auxPath,""))
				AttachTrail(rIndex);
		}

		
		SDKHook(iEntity, SDKHook_StartTouch, OnStartTouch);
		
		g_RocketEnt[rIndex].owner = 0;
		g_RocketEnt[rIndex].target = SearchTarget(rIndex);
		
		if( !IsValidAliveClient(g_RocketEnt[rIndex].target ))
		{
			AcceptEntityInput(iEntity, "Kill");
			g_RocketEnt[rIndex].entity = -1;
			return;
		}
			
		g_ClientAimed[g_RocketEnt[rIndex].target]++;
		
		EmitSoundClientDB(g_RocketEnt[rIndex].target, rsnd_alert ,rIndex,false);
		EmitSoundAllDB( rsnd_spawn,rIndex,true);
		if(g_RocketClass[class].snd_beep_use)
			g_RocketEnt[rIndex].beeptimer = CreateTimer(g_RocketClass[class].snd_beep_delay,RocketBeep,rIndex,TIMER_REPEAT);
		
		//Observer point
		/*if(IsValidEntity(g_observer))
		{
			TeleportEntity(g_observer, fPosition, fAngles, Float:{0.0, 0.0, 0.0});
			SetVariantString("!activator");
			AcceptEntityInput(g_observer, "SetParent", g_RocketEnt);
		}*/
		
		g_lastSpawned = rocketTeam;
		g_canSpawn = false;
		RenderHud();
		CreateTimer(g_spawn_delay,AllowSpawn);
		LogMessage("Fired in the rocket slot %d).",rIndex);
		
	}
}

public void AttachTrail(int rIndex)
{
	int index = EntRefToEntIndex(g_RocketEnt[rIndex].entity);
	if (index == INVALID_ENT_REFERENCE)
		return;		
	int trail = CreateEntityByName("env_spritetrail");
	
	int colornum = -1;
	if(useMultiColor())
		colornum = rIndex;
	if (!IsValidEntity(trail)) 
		return;

	char strTargetName[MAX_NAME_LENGTH];
	Format(strTargetName,sizeof(strTargetName),"projectile%d",index);
	DispatchKeyValue(index, "targetname", strTargetName);
	DispatchKeyValue(trail, "parentname", strTargetName);
	DispatchKeyValueFloat(trail, "lifetime", 1.0);
	DispatchKeyValueFloat(trail, "endwidth", 15.0);
	DispatchKeyValueFloat(trail, "startwidth", 6.0);
	
	char trailMaterial[PLATFORM_MAX_PATH];
	if(colornum >= 0 && colornum < MAXMULTICOLORHUD)
		Format(trailMaterial,PLATFORM_MAX_PATH,"%s.vmt",g_mrc_trail[colornum]);
	else
	{
		g_RocketClass[g_RocketEnt[rIndex].class].GetTrail(trailMaterial,PLATFORM_MAX_PATH);
		Format(trailMaterial,PLATFORM_MAX_PATH,"%s.vmt",trailMaterial);
	}
	
	DispatchKeyValue(trail, "spritename", trailMaterial);
	DispatchKeyValue(trail, "renderamt", "255");

	if(colornum >= 0 && colornum < MAXMULTICOLORHUD && g_mrc_applycolor_trail[colornum])
		DispatchKeyValue(trail, "rendercolor", g_mrc_color[colornum]);
	else
		DispatchKeyValue(trail, "rendercolor", "255 255 255 255");
	DispatchKeyValue(trail, "rendermode", "3");

	DispatchSpawn(trail);

	float vec[3];
	GetEntPropVector(index, Prop_Data, "m_vecOrigin", vec);

	TeleportEntity(trail, vec, NULL_VECTOR, NULL_VECTOR);

	SetVariantString(strTargetName);
	AcceptEntityInput(trail, "SetParent"); 
	SetEntPropFloat(trail, Prop_Send, "m_flTextureRes", 0.05);
	return;
}

public void AttachLight(int rIndex)
{
	int index = EntRefToEntIndex(g_RocketEnt[rIndex].entity);
	if (index == INVALID_ENT_REFERENCE)
		return;	
	
	int colornum = -1;
	if(!useMultiColor())
		return;
	colornum = rIndex;
	int iLightEntity = CreateEntityByName("light_dynamic");
	if (IsValidEntity(iLightEntity))
	{
		DispatchKeyValue(iLightEntity, "inner_cone", "0");
		DispatchKeyValue(iLightEntity, "cone", "80");
		DispatchKeyValue(iLightEntity, "brightness", "10");
		DispatchKeyValueFloat(iLightEntity, "spotlight_radius", 100.0);
		DispatchKeyValueFloat(iLightEntity, "distance", 150.0);
		DispatchKeyValue(iLightEntity, "_light", g_mrc_color[colornum]);
		DispatchKeyValue(iLightEntity, "pitch", "-90");
		DispatchKeyValue(iLightEntity, "style", "5");
		DispatchSpawn(iLightEntity);
		
		float fOrigin[3];
		GetEntPropVector(index, Prop_Data, "m_vecOrigin", fOrigin);
		
		fOrigin[2] += 40.0;
		TeleportEntity(iLightEntity, fOrigin, NULL_VECTOR, NULL_VECTOR);

		char strName[32];
		Format(strName, sizeof(strName), "target%i", index);
		DispatchKeyValue(index, "targetname", strName);
				
		DispatchKeyValue(iLightEntity, "parentname", strName);
		SetVariantString("!activator");
		AcceptEntityInput(iLightEntity, "SetParent", index, iLightEntity, 0);
		AcceptEntityInput(iLightEntity, "TurnOn");
	}	
	
}

/* RocketBeep()
**
** If the rocket is valid, beeps
** -------------------------------------------------------------------------- */
public Action RocketBeep(Handle timer, int rIndex)
{
	char auxPath[PLATFORM_MAX_PATH];
	int class = g_RocketEnt[rIndex].class;
	g_RocketClass[class].GetSndBeep(auxPath,PLATFORM_MAX_PATH);
	EmitSoundAllDB(rsnd_beep,rIndex,true);
	//EmitSoundDBAll(auxPath);
	return Plugin_Continue;
}

public Action OnStartTouch(int entity, int other)
{
	if (other > 0 && other <= MaxClients)
		return Plugin_Continue;
		
	int rIndex = GetRocketIndex(entity);
	int class = g_RocketEnt[rIndex].class;	
	//We check the bounce counter
	if (g_RocketEnt[rIndex].bounces >= g_RocketClass[class].maxbounce)
	{
		if(g_RocketClass[class].exp_use)
		{
			CreateExplosion(rIndex);
		}
		return Plugin_Continue;
	}
	
	SDKHook(entity, SDKHook_Touch, OnTouch);
	return Plugin_Handled;
}

public Action OnTouch(int entity, int other)
{
		
	float vOrigin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vOrigin);
	
	float vAngles[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", vAngles);
	
	float vVelocity[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vVelocity);
	
	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TEF_ExcludeEntity, entity);
	
	if(!TR_DidHit(trace))
	{
		CloseHandle(trace);
		return Plugin_Continue;
	}
	
	float vNormal[3];
	TR_GetPlaneNormal(trace, vNormal);
	
	CloseHandle(trace);
	
	float dotProduct = GetVectorDotProduct(vNormal, vVelocity);
	
	ScaleVector(vNormal, dotProduct);
	ScaleVector(vNormal, 2.0);
	
	float vBounceVec[3];
	SubtractVectors(vVelocity, vNormal, vBounceVec);
	
	float vNewAngles[3];
	GetVectorAngles(vBounceVec, vNewAngles);
	
	TeleportEntity(entity, NULL_VECTOR, vNewAngles, vBounceVec);

	
	int rIndex = GetRocketIndex(entity);
	int class = g_RocketEnt[rIndex].class;	
	g_RocketEnt[rIndex].bounces++;
	g_RocketEnt[rIndex].homing = false;
	
	EmitSoundAllDB(rsnd_bounce,rIndex,true);
	
	CreateTimer(g_RocketClass[class].bouncedelay,EnableHoming,rIndex);
	SDKUnhook(entity, SDKHook_Touch, OnTouch);
	return Plugin_Handled;
}

public bool TEF_ExcludeEntity(int entity, int contentsMask, int data)
{
	return (entity != data);
}

/* OnGameFrame()
**
** We set the player max speed on every frame, and also we set the spy's cloak on empty.
** Here we also check what to do with the rocket. We checks for deflects and modify the rocket's speed.
** -------------------------------------------------------------------------- */
public void OnGameFrame()
{
	if(!g_isDBmap) return;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidAliveClient(i))
		{
			SetEntPropFloat(i, Prop_Send, "m_flMaxspeed", g_player_speed);
			if(TF2_GetPlayerClass(i) == TFClass_Spy)
			{
				SetCloak(i, 1.0);
			}
		}
	}
	//Rocket Management
	if(!g_roundActive) return;
	
	int index;
	for(int i = 0; i < MAXROCKETS; i++)
	{
		index = EntRefToEntIndex(g_RocketEnt[i].entity);
		if (index == INVALID_ENT_REFERENCE)
			continue;
			
		//Check if the target is available
		if(!IsValidAliveClient(g_RocketEnt[i].target))
		{
			g_ClientAimed[g_RocketEnt[i].target]--;
			g_RocketEnt[i].target = SearchTarget(i);
		}
		int class = g_RocketEnt[i].class;
		//Check deflects
		int rDef  = GetEntProp(index, Prop_Send, "m_iDeflected") - 1;
		float aux_mul = 0.0;
		if(rDef > g_RocketEnt[i].deflects)
		{
			
			float fViewAngles[3], fDirection[3];
			GetClientEyeAngles(g_RocketEnt[i].target, fViewAngles);
			GetAngleVectors(fViewAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
			g_RocketEnt[i].SetDirection(fDirection);
			//CopyVectors(fDirection, g_RocketDirection);
			
			g_ClientAimed[g_RocketEnt[i].target]--;
			g_RocketEnt[i].target = SearchTarget(i);
			g_ClientAimed[g_RocketEnt[i].target]++;
			
			g_RocketEnt[i].deflects++;
			g_RocketEnt[i].bounces = 0;
			EmitSoundClientDB(g_RocketEnt[i].target, rsnd_alert ,i,false);
			if(g_RocketEnt[i].aimed && g_RocketClass[class].snd_aimed_use)
				EmitSoundAllDB(rsnd_aimed,i,false);
			else
			{
				int rTeam = GetEntProp(index, Prop_Send, "m_iTeamNum", 1);
				if(rTeam == TEAM_RED)
					EmitSoundAllDB(rsnd_bludeflect,i,true);
				else
					EmitSoundAllDB(rsnd_reddeflect,i,true);
			}
			g_RocketEnt[i].homing = false;
			g_RocketEnt[i].owner = GetEntPropEnt(index, Prop_Send, "m_hOwnerEntity");
			CreateTimer(g_RocketClass[class].deflectdelay,EnableHoming,i);
			RenderHud();
		}
		//If isn't a deflect then we have to modify the rocket's direction and velocity
		else
		{
			if(g_RocketEnt[i].homing)
			{
				if(IsValidAliveClient(g_RocketEnt[i].target))
				{
					float fDirectionToTarget[3], rocketDirection[3];
					g_RocketEnt[i].GetDirection(rocketDirection);
					
					CalculateDirectionToClient(index, g_RocketEnt[i].target, fDirectionToTarget);
					float turnrate = g_RocketClass[class].turnrate + g_RocketClass[class].turnrateinc * g_RocketEnt[i].deflects;
					LerpVectors(rocketDirection, fDirectionToTarget, rocketDirection, turnrate);
					
					g_RocketEnt[i].SetDirection(rocketDirection);
				}
			}
		}
		
		if(g_RocketEnt[i].homing)
		{
			float rocketDirection[3];
			g_RocketEnt[i].GetDirection(rocketDirection);
			float fAngles[3]; GetVectorAngles(rocketDirection, fAngles);
			float fVelocity[3]; CopyVectors(rocketDirection, fVelocity);
			
			if(aux_mul == 0.0)
				aux_mul = g_RocketClass[class].speed + g_RocketClass[class].speedinc * g_RocketEnt[i].deflects;
				
			if(g_RocketClass[class].allowaimed && g_RocketEnt[i].aimed)
				aux_mul = g_RocketClass[class].aimedspeed;
			
			float damage = g_RocketClass[class].damage + g_RocketClass[class].damageinc * g_RocketEnt[i].deflects;
			SetEntDataFloat(index, FindSendPropOffs("CTFProjectile_Rocket", "m_iDeflected") + 4, damage, true);	
				
			
			if(g_RocketClass[class].size > 0.0 && g_RocketClass[class].sizeinc > 0.0)
			{
				float size = g_RocketClass[class].size + g_RocketClass[class].sizeinc * g_RocketEnt[i].deflects;
				SetEntPropFloat(index, Prop_Send, "m_flModelScale", size);
			}
			g_RocketEnt[i].speed = aux_mul;
			fVelocity[0] = rocketDirection[0]*aux_mul;
			fVelocity[1] = rocketDirection[1]*aux_mul;
			fVelocity[2] = rocketDirection[2]*aux_mul;
			SetEntPropVector(index, Prop_Data, "m_vecAbsVelocity", fVelocity);
			SetEntPropVector(index, Prop_Send, "m_angRotation", fAngles);
		}
		
	}
}

/* EnableHoming()
**
** Timer used re-enable the rocket's movement 
** -------------------------------------------------------------------------- */
public Action EnableHoming(Handle timer, int rIndex)
{
	g_RocketEnt[rIndex].homing = true;
}

public OnEntityCreated(entity, const String:classname[])
{
	if(!g_isDBmap) return;
	if(!StrEqual("tf_ammo_pack",classname)) return;
	
	int dissolver = CreateEntityByName("env_entity_dissolver");

	if (dissolver == -1) return;
	
	DispatchKeyValue(dissolver, "dissolvetype", "0");
	DispatchKeyValue(dissolver, "magnitude", "1");
	DispatchKeyValue(dissolver, "target", "!activator");

	AcceptEntityInput(dissolver, "Dissolve", entity);
	AcceptEntityInput(dissolver, "Kill");
}

/* OnEntityDestroyed()
**
** We check if the rocket got destroyed, and then fire a timer for a new rocket.
** -------------------------------------------------------------------------- */
public OnEntityDestroyed(entity)
{
	if(!g_isDBmap) return;
	
	int rIndex = GetRocketIndex(EntIndexToEntRef(entity));
	if(rIndex == -1) return;
	

	g_RocketEnt[rIndex].entity = INVALID_ENT_REFERENCE;
	g_RocketEnt[rIndex].target = -1;
	g_RocketEnt[rIndex].owner = -1;
	g_RocketEnt[rIndex].class = -1;
	g_RocketEnt[rIndex].bounces = 0;
	g_RocketEnt[rIndex].deflects = -1;
	g_RocketEnt[rIndex].speed = -1.0;
	g_RocketEnt[rIndex].aimed = false;
	g_RocketEnt[rIndex].homing = false;
	CloseHandle (g_RocketEnt[rIndex].beeptimer);
	RenderHud();
	if(g_roundActive)
	{
		CreateTimer(g_spawn_delay, TryFireRocket);

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

/* CmdShockwave()
**
** Creates a huge shockwave at the location of the client, with the given
** parameters.
** -------------------------------------------------------------------------- */
public CreateExplosion(rIndex)
{
	int class = g_RocketEnt[rIndex].class;
	float fPosition[3]; 
	int index = EntRefToEntIndex(g_RocketEnt[rIndex].entity);
	if (index == INVALID_ENT_REFERENCE)
		return;
	int	iTeam = GetEntProp(index, Prop_Send, "m_iTeamNum", 1);
	GetEntPropVector(index, Prop_Data, "m_vecOrigin", fPosition);
		
	switch (GetRandomInt(0, 4))
	{
		case 0: { PlayParticle(fPosition, PARTICLE_NUKE_1_ANGLES, PARTICLE_NUKE_1); }
		case 1: { PlayParticle(fPosition, PARTICLE_NUKE_2_ANGLES, PARTICLE_NUKE_2); }
		case 2: { PlayParticle(fPosition, PARTICLE_NUKE_3_ANGLES, PARTICLE_NUKE_3); }
		case 3: { PlayParticle(fPosition, PARTICLE_NUKE_4_ANGLES, PARTICLE_NUKE_4); }
		case 4: { PlayParticle(fPosition, PARTICLE_NUKE_5_ANGLES, PARTICLE_NUKE_5); }
	}
	PlayParticle(fPosition, PARTICLE_NUKE_COLLUMN_ANGLES, PARTICLE_NUKE_COLLUMN);
		
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if(IsValidAliveClient(iClient) && GetClientTeam(iClient) != iTeam)
		{
			float fPlayerPosition[3]; 
			GetClientEyePosition(iClient, fPlayerPosition);
			float fDistanceToShockwave = GetVectorDistance(fPosition, fPlayerPosition);
			
			if (fDistanceToShockwave < g_RocketClass[class].exp_radius)
			{
				float fImpulse[3], fFinalPush;
				int iFinalDamage;
				fImpulse[0] = fPlayerPosition[0] - fPosition[0];
				fImpulse[1] = fPlayerPosition[1] - fPosition[1];
				fImpulse[2] = fPlayerPosition[2] - fPosition[2];
				NormalizeVector(fImpulse, fImpulse);
				if (fImpulse[2] < 0.4) { fImpulse[2] = 0.4; NormalizeVector(fImpulse, fImpulse); }
				
				if (fDistanceToShockwave < g_RocketClass[class].exp_fallof)
				{
					fFinalPush = g_RocketClass[class].exp_push;
					iFinalDamage = RoundFloat(g_RocketClass[class].exp_damage);
				}
				else
				{
					float fImpact = (1.0 - ((fDistanceToShockwave - g_RocketClass[class].exp_fallof) / ( g_RocketClass[class].exp_radius - g_RocketClass[class].exp_fallof)));
					fFinalPush   = fImpact * g_RocketClass[class].exp_push;
					iFinalDamage = RoundToFloor(fImpact * g_RocketClass[class].exp_damage);
				}
				ScaleVector(fImpulse, fFinalPush);
				SetEntPropVector(iClient, Prop_Data, "m_vecAbsVelocity", fImpulse);
				
				Handle hDamage = CreateDataPack();
				WritePackCell(hDamage, iClient);
				WritePackCell(hDamage, iFinalDamage);
				CreateTimer(0.1, ApplyDamage, hDamage, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	
	EmitSoundAllDB(rsnd_exp,rIndex,false);
}
/* ApplyDamage()
**
** Applies a damage to a player.
** -------------------------------------------------------------------------- */
public Action:ApplyDamage(Handle:hTimer, any:hDataPack)
{
    ResetPack(hDataPack, false);
    int  iClient = ReadPackCell(hDataPack);
    int iDamage = ReadPackCell(hDataPack);
    CloseHandle(hDataPack);
    SlapPlayer(iClient, iDamage, true);
}
/* PlayParticle()
**
** Plays a particle system at the given location & angles.
** -------------------------------------------------------------------------- */
stock PlayParticle(Float:fPosition[3], Float:fAngles[3], String:strParticleName[], Float:fEffectTime = 5.0, Float:fLifeTime = 9.0)
{
    int iEntity = CreateEntityByName("info_particle_system");
    if (iEntity && IsValidEdict(iEntity))
    {
        TeleportEntity(iEntity, fPosition, fAngles, NULL_VECTOR);
        DispatchKeyValue(iEntity, "effect_name", strParticleName);
        ActivateEntity(iEntity);
        AcceptEntityInput(iEntity, "Start");
        CreateTimer(fEffectTime, StopParticle, EntIndexToEntRef(iEntity));
        CreateTimer(fLifeTime, KillParticle, EntIndexToEntRef(iEntity));
    }
    else
    {
        LogError("ShowParticle: could not create info_particle_system");
    }    
}
/* StopParticle()
**
** Turns of the particle system. Automatically called by PlayParticle
** -------------------------------------------------------------------------- */
public Action:StopParticle(Handle:hTimer, any:iEntityRef)
{
    if (iEntityRef != INVALID_ENT_REFERENCE)
    {
        int iEntity = EntRefToEntIndex(iEntityRef);
        if (iEntity && IsValidEntity(iEntity))
        {
            AcceptEntityInput(iEntity, "Stop");
        }
    }
}

/* KillParticle()
**
** Destroys the particle system. Automatically called by PlayParticle
** -------------------------------------------------------------------------- */
public Action:KillParticle(Handle:hTimer, any:iEntityRef)
{
    if (iEntityRef != INVALID_ENT_REFERENCE)
    {
        int iEntity = EntRefToEntIndex(iEntityRef);
        if (iEntity && IsValidEntity(iEntity))
        {
            RemoveEdict(iEntity);
        }
    }
}

/* PrecacheParticle()
**
** Forces the client to precache a particle system.
** -------------------------------------------------------------------------- */
stock PrecacheParticle(String:strParticleName[])
{
    PlayParticle(Float:{0.0, 0.0, 0.0}, Float:{0.0, 0.0, 0.0}, strParticleName, 0.1, 0.1);
}

/* ClearHud()
**
** Clears the hud's synchronizers on game end.
** -------------------------------------------------------------------------- */

public void ClearHud()
{
	if(useMultiColor() || g_max_rockets == 1)
		for( int c = 0; c < g_max_rockets; c++)
			for(int client = 1; client <= MaxClients; client++)
				if(IsValidAliveClient(client))
					ClearSyncHud(client,g_HudSyncs[c]);
}
/* RenderHud()
**
** This will render the hud for 30 secs (called on start/rocket fired/ rocket deflected and rocket destroyed).
** -------------------------------------------------------------------------- */
public void RenderHud()
{
	if(!g_hud_show) return;
	//Multi Color hud
	if(useMultiColor())
	{
		int ncolor[3];
		char strHud[PLATFORM_MAX_PATH];
		for( int c = 0; c < g_max_rockets; c++)
		{
			GetIntColor(g_mrc_color[c],ncolor);
			SetHudTextParams(g_hud_x,g_hud_y+ c*2*HUD_LINE_SEPARATION,30.0,ncolor[0],ncolor[1],ncolor[2],255, 0, 0.0, 0.0, 0.0);
			
			GetHudString(strHud, PLATFORM_MAX_PATH, c, true);
			
			for(int client = 1; client <= MaxClients; client++)
				if(IsValidClient(client))
					ShowSyncHudText(client, g_HudSyncs[c], "%s",strHud);
		}
	
	}
	//Just one rocket
	else if (g_max_rockets == 1)
	{
		int ncolor[3];
		char strHud[PLATFORM_MAX_PATH];
		
		GetIntColor(g_hud_color,ncolor);
		SetHudTextParams(g_hud_x,g_hud_y,30.0,ncolor[0],ncolor[1],ncolor[2],255, 0, 0.0, 0.0, 0.0);
		
		GetHudString(strHud, PLATFORM_MAX_PATH, 1, false);
		
		for(int client = 1; client <= MaxClients; client++)
			if(IsValidClient(client))
				ShowSyncHudText(client, g_HudSyncs[0], "%s",strHud);
	
	}
}

void GetIntColor(char[] strColor, int buffer[3])
{
	char scolor[3][8];
	ExplodeString(strColor," ",scolor,3,8);
	for(int i = 0; i < 3; i++)
		buffer[i] = StringToInt(scolor[i]);
}

void GetHudString(char[] strHud, int length, int rIndex, bool twoLines)
{
	char owner[MAX_NAME_LENGTH] = "-", target[MAX_NAME_LENGTH] = "-", speed[MAX_NAME_LENGTH] = "-",deflects[MAX_NAME_LENGTH] = "-";
	
	int index = EntRefToEntIndex(g_RocketEnt[rIndex].entity);
	if (index != INVALID_ENT_REFERENCE)
	{
		if( g_RocketEnt[rIndex].owner >= 0 && g_RocketEnt[rIndex].owner <= MaxClients )
		{
			if( g_RocketEnt[rIndex].owner == 0)
				Format(owner,MAX_NAME_LENGTH,"The server");
			else
				if(IsValidClient(g_RocketEnt[rIndex].owner))
					Format(owner,MAX_NAME_LENGTH,"%N",g_RocketEnt[rIndex].owner);
		}
		if(IsValidClient(g_RocketEnt[rIndex].target))
			Format(target,MAX_NAME_LENGTH,"%N",g_RocketEnt[rIndex].target);
		if( g_RocketEnt[rIndex].speed >= 0)
			Format(speed,MAX_NAME_LENGTH,"%.1f",g_RocketEnt[rIndex].speed);
		if( g_RocketEnt[rIndex].deflects >= 0)
			Format(deflects,MAX_NAME_LENGTH,"%d",g_RocketEnt[rIndex].deflects);
			
	}
	if(twoLines)
		Format(strHud, length, "<- %s | Defs: %s \n-> %s | S: %s",owner,deflects,target,speed);
	else
		Format(strHud, length, " Owner: %s \n Target: %s \n Deflects: %s \n Speed: %s",owner,target,deflects,speed);
	
}

bool useMultiColor()
{
	if(g_max_rockets > 1 && g_max_rockets <= MAXMULTICOLORHUD && g_allow_multirocketcolor)
		return true;
	return false;
}


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
	
	ProcessListeners(true);
	g_SndRoundStart.Clear();
	g_SndOnDeath.Clear();
	g_SndOnKill.Clear();
	g_SndLastAlive.Clear();
	g_RestrictedWeps.Clear();
	g_CommandToBlock.Clear();
	g_BlockOnlyOnPreparation.Clear();
	g_class_chance.Clear();
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
public Action Command_Block(int client, const char[] command, int argc)
{
	if(g_isDBmap)
		return Plugin_Stop;
	return Plugin_Continue;
}

/* Command_Block_PreparationOnly()
**
** Blocks a command, but only if we are on preparation 
** -------------------------------------------------------------------------- */
public Action Command_Block_PreparationOnly(client, const char[] command, int argc)
{
	if(g_isDBmap && g_onPreparation)
		return Plugin_Stop;
	return Plugin_Continue;
}


/* EmitSoundClientDB()
**
** Emits a to a client checking if the sound is empty, using the rocket's sound enum.
** -------------------------------------------------------------------------- */
void EmitSoundClientDB(int client, int rocketsnd, int rIndex, bool fromEntity)
{
	int index = EntRefToEntIndex(g_RocketEnt[rIndex].entity);
	if (index == INVALID_ENT_REFERENCE)
		return;
	char strFile[PLATFORM_MAX_PATH]="";
	GetSndString(strFile,PLATFORM_MAX_PATH,rIndex,rocketsnd);
	
	if(StrEqual(strFile, ""))
		return;
	if(fromEntity)
		EmitSoundToClient(client,strFile, index, _, SNDLEVEL_TRAIN,_,SOUND_ALERT_VOL);
	else
		EmitSoundToClient(client,strFile, _, _, SNDLEVEL_TRAIN,_,SOUND_ALERT_VOL);

}
/* EmitSoundAllDB()
**
** Emits a to everyone checking if the sound is empty, using the rocket's sound enum.
** -------------------------------------------------------------------------- */
void EmitSoundAllDB(int rocketsnd, int rIndex, bool fromEntity)
{	
	int index = EntRefToEntIndex(g_RocketEnt[rIndex].entity);
	if (index == INVALID_ENT_REFERENCE)
		return;
	char strFile[PLATFORM_MAX_PATH]="";
	GetSndString(strFile,PLATFORM_MAX_PATH,rIndex,rocketsnd);
	if(StrEqual(strFile, ""))
		return;
	if(fromEntity)
		EmitSoundToAll(strFile, index, _, SNDLEVEL_TRAIN,_,SOUND_ALERT_VOL);
	else
		EmitSoundToAll(strFile, _, _, SNDLEVEL_TRAIN,_,SOUND_ALERT_VOL);
}

/* GetSndString()
**
** Gets the sound string of the enum passed as argument.
** -------------------------------------------------------------------------- */
void GetSndString(char[] buffer, int length, int rIndex, int rocketsnd)
{
	Format(buffer, length, "");
	int class = g_RocketEnt[rIndex].class;
	if(rocketsnd == rsnd_spawn)
	{
		if(g_RocketClass[class].snd_spawn_use)
			g_RocketClass[class].GetSndSpawn(buffer,length);
	}
	else if(rocketsnd == rsnd_alert)
	{
		if(g_RocketClass[class].snd_alert_use)
			g_RocketClass[class].GetSndAlert(buffer,length);
	}
	else if(rocketsnd == rsnd_bludeflect)
	{
		if(g_RocketClass[class].snd_deflect_use)
			g_RocketClass[class].GetSndDeflectBlue(buffer,length);
	}
	else if(rocketsnd == rsnd_reddeflect)
	{
		if(g_RocketClass[class].snd_deflect_use)
			g_RocketClass[class].GetSndDeflectRed(buffer,length);
	}
	else if(rocketsnd == rsnd_beep)
	{
		if(g_RocketClass[class].snd_beep_use)
			g_RocketClass[class].GetSndBeep(buffer,length);
	}
	else if(rocketsnd == rsnd_aimed)
	{
		if(g_RocketClass[class].snd_aimed_use)
			g_RocketClass[class].GetSndAimed(buffer,length);
	}
	else if(rocketsnd == rsnd_bounce)
	{
		if(g_RocketClass[class].snd_bounce_use)
			g_RocketClass[class].GetSndBounce(buffer,length);
	}
	else if(rocketsnd == rsnd_exp)
	{
		g_RocketClass[class].GetExpSound(buffer,length);
	}
}

/* EmitRandomSound()
**
** Emits a random sound from a trie, it will be emitted for everyone is a client isn't passed.
** -------------------------------------------------------------------------- */
stock EmitRandomSound(StringMap sndTrie,client = -1)
{
	int trieSize = sndTrie.Size;
	//LogMessage("Emitting sound from trie with %d sounds.",trieSize);
	char key[4], sndFile[PLATFORM_MAX_PATH];
	IntToString(GetRandomInt(1,trieSize),key,sizeof(key));

	if(GetTrieString(sndTrie,key,sndFile,sizeof(sndFile)))
	{
		if(StrEqual(sndFile, ""))
			return;
			
		if(client != -1)
		{
			if(IsValidClient(client))
			{
				EmitSoundToClient(client,sndFile,_,_, SNDLEVEL_TRAIN);
			}
			else
				return;
		}
		else
		{
			EmitSoundToAll(sndFile, _, _, SNDLEVEL_TRAIN);
		}
	}
}
/* TF2_SwitchtoSlot()
**
** Changes the client's slot to the desired one.
** -------------------------------------------------------------------------- */
stock void TF2_SwitchtoSlot(int client, int slot)
{
	if (slot >= 0 && slot <= 5 && IsValidAliveClient(client))
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

/* IsValidAliveClient()
**
** Check if the client is valid and alive/ingame
** -------------------------------------------------------------------------- */
stock bool IsValidAliveClient(int client)
{
	if(client < 0 || client > MaxClients || !IsClientConnected(client) ||	!IsClientInGame(client) || !IsPlayerAlive(client))
			return false;
	return true;
}

/* IsValidClient()
**
** Check if the client is valid and alive/ingame
** -------------------------------------------------------------------------- */
stock bool IsValidClient(int client)
{
	if(client < 0 || client > MaxClients || !IsClientConnected(client) ||	!IsClientInGame(client) )
			return false;
	return true;
}
/* GetAlivePlayersCount()
**
** Get alive players of a team (ignoring one)
** -------------------------------------------------------------------------- */
stock GetAlivePlayersCount(team,ignore=-1) 
{
	int count = 0, i;

	for( i = 1; i <= MaxClients; i++ ) 
		if(IsValidAliveClient(i) && GetClientTeam(i) == team && i != ignore) 
			count++; 

	return count; 
}  

/* GetAlivePlayersCount()
**
** Get last player of a team (ignoring one), asuming that GetAlivePlayersCountwas used before.
** -------------------------------------------------------------------------- */
stock GetLastPlayer(team,ignore=-1) 
{
	for(int i = 1; i <= MaxClients; i++ ) 
		if(IsValidAliveClient(i) && GetClientTeam(i) == team && i != ignore) 
			return i;
	return -1;
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

/* CleanString()
**
** Cleans the given string from any illegal character.
** -------------------------------------------------------------------------- */
stock CleanString(String:strBuffer[])
{
	// Cleanup any illegal characters
	int Length = strlen(strBuffer);
	for (int iPos=0; iPos<Length; iPos++)
	{
		switch(strBuffer[iPos])
		{
			case '\r': strBuffer[iPos] = ' ';
			case '\n': strBuffer[iPos] = ' ';
			case '\t': strBuffer[iPos] = ' ';
		}
	}
	
	// Trim string
	TrimString(strBuffer);
}
