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
#define HUD_LINE_SEPARATION 0.03

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
	if(kv.JumpToKey("sounds")) 
	{
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
		kv.GoBack();
	}
	//Explosion
	if(kv.JumpToKey("explosion"))
	{
		defClass.exp_use = !!kv.GetNum("CreateBigExplosion",0);
		defClass.exp_damage = kv.GetNum("Damage",200);
		defClass.exp_push = kv.GetNum("PushStrength",1000);
		defClass.exp_radius = kv.GetNum("Radius",1000);
		defClass.exp_fallof = kv.GetNum("FallOfRadius",600);
		kv.GoBack();
	}
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
		if(kv.JumpToKey("sounds"))
		{
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
			kv.GoBack();
		}
		//Explosion
		if(kv.JumpToKey("explosion"))
		{
			g_RocketClass[count].exp_use = !!kv.GetNum("CreateBigExplosion",defClass.exp_use);
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
        decl String:strDepFileName[PLATFORM_MAX_PATH];
        Format(strDepFileName, sizeof(strDepFileName), "%s.res", strFileName);
        
        if (FileExists(strDepFileName))
        {
            // Open stream, if possible
            new Handle:hStream = OpenFile(strDepFileName, "r");
            if (hStream == INVALID_HANDLE) { LogMessage("Error, can't read file containing model dependencies."); return; }
            
            while(!IsEndOfFile(hStream))
            {
                decl String:strBuffer[PLATFORM_MAX_PATH];
                ReadFileLine(hStream, strBuffer, sizeof(strBuffer));
                CleanString(strBuffer);
                
                // If file exists...
                if (FileExists(strBuffer, true))
                {
                    // Precache depending on type, and add to download table
                    if (StrContains(strBuffer, ".vmt", false) != -1)      PrecacheDecal(strBuffer, true);
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
		if(IsClientInGame(i) && IsPlayerAlive(i))
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
	for(int i = 1; i <= MaxClients; i++)
		if(IsClientInGame(i) && IsPlayerAlive(i))
		{
			SetEntityMoveType(i, MOVETYPE_WALK);
			g_ClientAimed[i] = 0;
		}
	g_onPreparation = false;
	g_roundActive = true;
	g_canSpawn = true;
	if(GetRandomInt(0,1))
		g_lastSpawned = TEAM_RED;
	else
		g_lastSpawned = TEAM_BLUE;
	
	FireRocket();

}

/* OnRoundEnd()
**
** Here we destroy the rocket.
** -------------------------------------------------------------------------- */
public Action OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	g_roundActive=false;
	for(int i = 0; i < g_max_rockets; i++)
	{
		if(IsValidEntity(g_RocketEnt[i].entity))
			AcceptEntityInput(g_RocketEnt[i].entity, "Kill");
	}
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
	if(g_canEmitKillSound)
	{
		EmitRandomSound(g_SndOnKill,killer);
		g_canEmitKillSound = false;
		CreateTimer(g_OnKillDelay, ReenableKillSound);
	}
	
	int aliveTeammates = GetAlivePlayersCount(GetClientTeam(client),client);
	if(aliveTeammates == 1)
		EmitRandomSound(g_SndLastAlive,GetLastPlayer(GetClientTeam(client),client));
	

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
			g_RedSpawn = iEntity;
		if ((StrContains(strName, "rocket_spawn_blue") != -1) || (StrContains(strName, "tf_dodgeball_blu") != -1))
			g_BlueSpawn = iEntity;
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
	for(int i = 0; i < g_max_rockets; i++)
	{
		//LogMessage("Rocket slot %d, entity = %d",i,g_RocketEnt[i].entity);
		if(!IsValidEntity(g_RocketEnt[i].entity))
			return i;
	}
	return -1;
}

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
	if(g_RocketEnt[rIndex].entity <= 0) return -1;
	int rTeam = GetEntProp(g_RocketEnt[rIndex].entity, Prop_Send, "m_iTeamNum", 1);
	int class = g_RocketEnt[rIndex].class;
	//Check by aim
	if(g_RocketClass[class].allowaimed)
	{
		int rOwner = GetEntPropEnt(g_RocketEnt[rIndex].entity, Prop_Send, "m_hOwnerEntity");
		if(rOwner != 0)
		{
			int cAimed = GetClientAimTarget(rOwner, true);
			if( cAimed > 0 && cAimed < MaxClients && IsPlayerAlive(cAimed) && GetClientTeam(cAimed) != rTeam )
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
		if(!IsClientConnected(i) || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) == rTeam || g_ClientAimed[i] > 0)
			continue;
		possiblePlayers[possibleNumber] = i;
		possibleNumber++;
	}
	
	//If there weren't any player the could be targeted the we try even with already aimed clients.
	if(possibleNumber == 0)
	{
		for(int i = 1; i <= MaxClients ; i++)
		{
			if(!IsClientConnected(i) || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) == rTeam)
				continue;
			possiblePlayers[possibleNumber] = i;
			possibleNumber++;
		}
		if(possibleNumber == 0)
		{
			if(g_roundActive)
				LogError("[DB] Tried to fire a rocket but there weren't any player available.");
			return -1;
		}
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
		GetEntPropVector(g_RocketEnt[rIndex].entity, Prop_Send, "m_vecOrigin", rPos);
		
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
** Timer used to spawn a new rocket.
** -------------------------------------------------------------------------- */
public Action TryFireRocket(Handle timer, int data)
{
	if(!g_canSpawn)
		return;
	FireRocket();

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
	//LogMessage("Going to spawn the rocket slot %d).",rIndex);
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
		g_RocketEnt[rIndex].entity = iEntity;
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
		
		char auxPath[PLATFORM_MAX_PATH];
		g_RocketClass[class].GetModel(auxPath,PLATFORM_MAX_PATH);
		if(!StrEqual(auxPath,""))
			SetEntityModel(iEntity, auxPath);
		
		if(g_RocketClass[class].size > 0.0)
			SetEntPropFloat(iEntity, Prop_Send, "m_flModelScale", g_RocketClass[class].size);

		
		SDKHook(iEntity, SDKHook_StartTouch, OnStartTouch);
		
		g_RocketEnt[rIndex].target = SearchTarget(rIndex);
		g_ClientAimed[g_RocketEnt[rIndex].target]++;
		
		if(g_RocketClass[class].snd_spawn_use)
		{
			g_RocketClass[class].GetSndSpawn(auxPath,PLATFORM_MAX_PATH);
			EmitSoundDBAll(auxPath);
		}
		
		if(g_RocketClass[class].snd_alert_use)
		{
			g_RocketClass[class].GetSndAlert(auxPath,PLATFORM_MAX_PATH);
			EmitSoundDB(g_RocketEnt[rIndex].target,auxPath);
		}
		if(g_RocketClass[class].snd_beep_use)
			g_RocketEnt[rIndex].beeptimer = CreateTimer(g_RocketClass[class].snd_beep_delay,RocketBeep,rIndex,TIMER_REPEAT);
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
		//LogMessage("Fired a rocket, class= %d",class);
		
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
	EmitSoundDB(g_RocketEnt[rIndex].target,auxPath);
	return Plugin_Continue;
}


public Action OnStartTouch(int entity, int other)
{
	if (other > 0 && other <= MaxClients)
		return Plugin_Continue;
	
	int rIndex = GetRocketIndex(entity);
	int class = g_RocketEnt[rIndex].class;
	// Only allow a rocket to bounce x times.
	if (g_RocketEnt[rIndex].bounces >= g_RocketClass[class].maxbounce)
		return Plugin_Continue;
	
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
	g_RocketEnt[rIndex].bounces++;
	g_RocketEnt[rIndex].homing = false;
	int class = g_RocketEnt[rIndex].class;
	
	if(g_RocketClass[class].snd_bounce_use)
	{
		char auxPath[PLATFORM_MAX_PATH];
		g_RocketClass[class].GetSndBounce(auxPath,PLATFORM_MAX_PATH);
		EmitSoundDBAll(auxPath);
	}
		
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
		if(IsClientInGame(i) && IsPlayerAlive(i))
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
	
	for(int i = 0; i < MAXROCKETS; i++)
	{
		if(g_RocketEnt[i].entity < 0)
			continue;
			
		//Check if the target is available
		if(!IsValidAliveClient(g_RocketEnt[i].target))
		{
			g_ClientAimed[g_RocketEnt[i].target]--;
			g_RocketEnt[i].target = SearchTarget(i);
		}
		int class = g_RocketEnt[i].class;
		//Check deflects
		int rDef  = GetEntProp(g_RocketEnt[i].entity, Prop_Send, "m_iDeflected") - 1;
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
			
			
			if(g_RocketEnt[i].aimed && g_RocketClass[class].snd_aimed_use)
			{
				char auxPath[PLATFORM_MAX_PATH];
				g_RocketClass[class].GetSndAimed(auxPath,PLATFORM_MAX_PATH);
				EmitSoundDBAll(auxPath);
				PrintCenterTextAll("%s",g_hud_aimed_text);
			}
			else if(g_RocketClass[class].snd_deflect_use)
			{
				char auxPath[PLATFORM_MAX_PATH];
				int rTeam = GetEntProp(g_RocketEnt[i].entity, Prop_Send, "m_iTeamNum", 1);
				if(rTeam == TEAM_RED)
					g_RocketClass[class].GetSndDeflectBlue(auxPath,PLATFORM_MAX_PATH);
				else
					g_RocketClass[class].GetSndDeflectRed(auxPath,PLATFORM_MAX_PATH);
				EmitSoundDBAll(auxPath);
			}
			/*
			if(IsValidAliveClient(g_RocketEnt[i].target))
			{
				//EmitSoundToClient(g_RocketTarget, SOUND_ALERT, _, _, _, _, SOUND_ALERT_VOL);	

				if(g_RocketEnt[i].aimed)
				{
				
					EmitSoundToClient(g_RocketTarget, SOUND_SPAWN, _, _, _, _, SOUND_ALERT_VOL);	
					if (rOwner > 0 && rOwner <= MaxClients)
						EmitSoundToClient(rOwner, SOUND_SPAWN, _, _, _, _, SOUND_ALERT_VOL);	
						
					SetHudTextParams(-1.0, -1.0, 1.5, ALERT_R, ALERT_G, ALERT_B, 255, 2, 0.28 , 0.1, 0.1);
					ShowSyncHudText(rOwner, g_HudSyncs[hud_SuperShot], "Super Shot!");
				}
			}*//*
			if(g_ShowInfo)
			{
				aux_mul = BASE_SPEED * g_SpeedMul * (1 + g_DeflectInc * rDef);
				ShowHud(10.0,aux_mul,g_DeflectCount,rOwner,g_RocketTarget);
			}*/
			g_RocketEnt[i].homing = false;
			g_RocketEnt[i].owner = GetEntPropEnt(g_RocketEnt[i].entity, Prop_Send, "m_hOwnerEntity");
			CreateTimer(g_RocketClass[class].deflectdelay,EnableHoming,i);
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
					
					CalculateDirectionToClient(g_RocketEnt[i].entity, g_RocketEnt[i].target, fDirectionToTarget);
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
				//aux_mul = BASE_SPEED * g_SpeedMul * (1 + g_DeflectInc * rDef);
			if(g_RocketClass[class].allowaimed && g_RocketEnt[i].aimed)
				aux_mul = g_RocketClass[class].aimedspeed;
			
			float damage = g_RocketClass[class].damage + g_RocketClass[class].damageinc * g_RocketEnt[i].deflects;
			SetEntDataFloat(g_RocketEnt[i].entity, FindSendPropOffs("CTFProjectile_Rocket", "m_iDeflected") + 4, damage, true);	
				
			
			if(g_RocketClass[class].size > 0.0 && g_RocketClass[class].sizeinc > 0.0)
			{
				float size = g_RocketClass[class].size + g_RocketClass[class].sizeinc * g_RocketEnt[i].deflects;
				SetEntPropFloat(g_RocketEnt[i].entity, Prop_Send, "m_flModelScale", size);
			}
			fVelocity[0] = rocketDirection[0]*aux_mul;
			fVelocity[1] = rocketDirection[1]*aux_mul;
			fVelocity[2] = rocketDirection[2]*aux_mul;
			SetEntPropVector(g_RocketEnt[i].entity, Prop_Data, "m_vecAbsVelocity", fVelocity);
			SetEntPropVector(g_RocketEnt[i].entity, Prop_Send, "m_angRotation", fAngles);
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

/* OnEntityDestroyed()
**
** We check if the rocket got destroyed, and then fire a timer for a new rocket.
** -------------------------------------------------------------------------- */
public OnEntityDestroyed(entity)
{
	if(!g_isDBmap) return;
	if(!IsValidEntity(entity)) return;
	int rIndex = GetRocketIndex(entity);
	if(rIndex == -1) return;

	//int class = g_RocketEnt[rIndex].class;
	g_RocketEnt[rIndex].entity = -1;
	g_RocketEnt[rIndex].target = -1;
	g_RocketEnt[rIndex].owner = -1;
	g_RocketEnt[rIndex].class = -1;
	g_RocketEnt[rIndex].bounces = 0;
	g_RocketEnt[rIndex].deflects = 0;
	g_RocketEnt[rIndex].aimed = false;
	g_RocketEnt[rIndex].homing = false;
	CloseHandle (g_RocketEnt[rIndex].beeptimer);
	if(g_roundActive)
	{
		CreateTimer(g_spawn_delay, TryFireRocket);
		//LogMessage("Rocket %d destroyed (entity: %d).",rIndex,entity);
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

/* EmitSoundDBAll()
**
** Emits a to everyone checking if the sound is empty
** -------------------------------------------------------------------------- */
stock EmitSoundDBAll(char sndFile[PLATFORM_MAX_PATH])
{
	if(StrEqual(sndFile, ""))
		return;
	EmitSoundToAll(sndFile, _, _, SNDLEVEL_TRAIN);
}
/* EmitSoundDB()
**
** Emits a to everyone checking if the sound is empty
** -------------------------------------------------------------------------- */
stock EmitSoundDB(int client, char sndFile[PLATFORM_MAX_PATH])
{
	if(StrEqual(sndFile, ""))
		return;
	EmitSoundToClient(client,sndFile, _, _, SNDLEVEL_TRAIN);
}

/* EmitRandomSound()
**
** Emits a random sound from a trie, it will be emitted for everyone is a client isn't passed.
** -------------------------------------------------------------------------- */
stock EmitRandomSound(Handle:sndTrie,client = -1)
{
	new trieSize = GetTrieSize(sndTrie);
	
	new String:key[4], String:sndFile[PLATFORM_MAX_PATH];
	IntToString(GetRandomInt(1,trieSize),key,sizeof(key));

	if(GetTrieString(sndTrie,key,sndFile,sizeof(sndFile)))
	{
		if(StrEqual(sndFile, ""))
			return;
			
		if(client != -1)
		{
			if(client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
				EmitSoundToClient(client,sndFile,_,_, SNDLEVEL_TRAIN);
			else
				return;
		}
		else	
			EmitSoundToAll(sndFile, _, _, SNDLEVEL_TRAIN);
	}
}


/* GetAlivePlayersCount()
**
** Get alive players of a team (ignoring one)
** -------------------------------------------------------------------------- */
stock GetAlivePlayersCount(team,ignore=-1) 
{ 
	new count = 0, i;

	for( i = 1; i <= MaxClients; i++ ) 
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == team && i != ignore) 
			count++; 

	return count; 
}  

/* GetAlivePlayersCount()
**
** Get last player of a team (ignoring one), asuming that GetAlivePlayersCountwas used before.
** -------------------------------------------------------------------------- */
stock GetLastPlayer(team,ignore=-1) 
{ 
	for(new i = 1; i <= MaxClients; i++ ) 
		if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == team && i != ignore) 
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
    new Length = strlen(strBuffer);
    for (new iPos=0; iPos<Length; iPos++)
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
