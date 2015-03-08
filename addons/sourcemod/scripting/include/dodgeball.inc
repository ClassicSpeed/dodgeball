#if defined _tf2dodgeball_included
  #endinput
#endif
#define _tf2dodgeball_included

//Maximum values
#define MAXROCKETS 100
#define ROCKETCLASSNUM 26
#define MAXROCKETCLASS 25
#define DEF_C 25

//---Rocket Entities-----------------------------------------------

int g_RocketEntity[MAXROCKETS] = {-1,...};
int g_RocketEntClass[MAXROCKETS] = {-1,...};
int g_RocketBounces[MAXROCKETS] = {0,...};
int g_RocketTarget[MAXROCKETS] = {-1,...};
int g_RocketOwner[MAXROCKETS] = {-1,...};
bool g_RocketAimed[MAXROCKETS] = {false,...};
float g_RocketDirection[MAXROCKETS][3];
int g_DeflectCount[MAXROCKETS] = {0,...};
float g_RocketSpeed[MAXROCKETS] = {0.0,...};
bool g_HomingEnabled[MAXROCKETS] = {true,...};
Handle g_TimerBeep[MAXROCKETS] = {null,...};

methodmap RocketEnt
{
	public RocketEnt( int index )
	{
		return view_as<RocketEnt>( index );
	}
	property int index
	{
		public get() { return view_as<int>( this ); }
	}
	property int entity
	{
		public get() { return g_RocketEntity[ this.index ]; }
		public set( int ent ) { g_RocketEntity[ this.index ] = ent; }
	}
	property int class
	{
		public get() { return g_RocketEntClass[ this.index ]; }
		public set( int classnum ) { g_RocketEntClass[ this.index ] = classnum; }
	}
	property int bounces
	{
		public get() { return g_RocketBounces[ this.index ]; }
		public set( int bouncenum ) { g_RocketBounces[ this.index ] = bouncenum; }
	}
	property int target
	{
		public get() { return g_RocketTarget[ this.index ]; }
		public set( int client ) { g_RocketTarget[ this.index ] = client; }
	}
	property int owner
	{
		public get() { return g_RocketOwner[ this.index ]; }
		public set( int client ) { g_RocketOwner[ this.index ] = client; }
	}
	property bool aimed
	{
		public get() { return g_RocketAimed[ this.index ]; }
		public set( bool isAimed ) { g_RocketAimed[ this.index ] = isAimed; }
	}
	public void GetDirection(float dir[3])
	{
		for (int i = 0; i < 3; i++)
            dir[i] = g_RocketDirection[this.index][i];
    }
	public void SetDirection(float dir[3])
	{
		for (int i = 0; i < 3; i++)
            g_RocketDirection[this.index][i] = dir[i];
    }
	property int deflects
	{
		public get() { return g_DeflectCount[ this.index ]; }
		public set( int num ) { g_DeflectCount[ this.index ] = num; }
	}
	property float speed
	{
		public get() { return g_RocketSpeed[ this.index ]; }
		public set( float num ) { g_RocketSpeed[ this.index ] = num; }
	}
	property bool homing
	{
		public get() { return g_HomingEnabled[ this.index ]; }
		public set( bool isHoming ) { g_HomingEnabled[ this.index ] = isHoming; }
	}
	property Handle beeptimer
	{
		public get() { return g_TimerBeep[ this.index ]; }
		public set( Handle timer ) { g_TimerBeep[ this.index ] = timer; }
	}
}

//---Rocket Entities-----------------------------------------------


//Rocket Classes//
char g_class_name[ROCKETCLASSNUM][MAX_NAME_LENGTH];
char g_class_trail[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
char g_class_model[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
float g_class_size[ROCKETCLASSNUM];
float g_class_size_inc[ROCKETCLASSNUM];
float g_class_damage[ROCKETCLASSNUM];
float g_class_damage_inc[ROCKETCLASSNUM];
float g_class_speed[ROCKETCLASSNUM];
float g_class_speed_inc[ROCKETCLASSNUM];
float g_class_turnrate[ROCKETCLASSNUM];
float g_class_turnrate_inc[ROCKETCLASSNUM];
float g_class_deflect_delay[ROCKETCLASSNUM];
bool g_class_target_closest[ROCKETCLASSNUM];
bool g_class_aimed_allow[ROCKETCLASSNUM];
float g_class_aimed_speed[ROCKETCLASSNUM];
int g_class_bounce_max[ROCKETCLASSNUM];
float g_class_bounce_delay[ROCKETCLASSNUM];
//Rocket's sounds
bool g_class_sound_spawn_play[ROCKETCLASSNUM];
char g_class_sound_spawn[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
bool g_class_sound_alert_play[ROCKETCLASSNUM];
char g_class_sound_alert[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
bool g_class_sound_deflect_play[ROCKETCLASSNUM];
char g_class_sound_deflect_red[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
char g_class_sound_deflect_blue[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
bool g_class_sound_beep_play[ROCKETCLASSNUM];
char g_class_sound_beep[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
float g_class_sound_beep_interval[ROCKETCLASSNUM];
bool g_class_sound_bounce_play[ROCKETCLASSNUM];
char g_class_sound_bounce[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
bool g_class_sound_aimed_play[ROCKETCLASSNUM];
char g_class_sound_aimed[ROCKETCLASSNUM][PLATFORM_MAX_PATH];
//Explosion
bool g_class_explosion_create[ROCKETCLASSNUM];
float g_class_explosion_damage[ROCKETCLASSNUM];
float g_class_explosion_push_strength[ROCKETCLASSNUM];
float g_class_explosion_radius[ROCKETCLASSNUM];
float  g_class_explosion_fallof_radius[ROCKETCLASSNUM];
char g_class_explosion_sound[ROCKETCLASSNUM][PLATFORM_MAX_PATH];



methodmap RocketClass
{
	public RocketClass( int index )
	{
		return view_as<RocketClass>( index );
	}
	property int index
	{
		public get() { return view_as<int>( this ); }
	}
	
	public void GetName(char [] name, int length) { strcopy(name, length, g_class_name[this.index]); }
	public void SetName(char [] name) { strcopy(g_class_name[this.index], MAX_NAME_LENGTH, name); }
	
	public void GetTrail(char [] trail, int length) { strcopy(trail, length, g_class_trail[this.index]); }
	public void SetTrail(char [] trail) { strcopy(g_class_trail[this.index], PLATFORM_MAX_PATH, trail); }
	
	public void GetModel(char [] model, int length) { strcopy(model, length, g_class_model[this.index]); }
	public void SetModel(char [] model) { strcopy(g_class_model[this.index], PLATFORM_MAX_PATH, model); }
	
	property float size
	{
		public get() { return g_class_size[ this.index ]; }
		public set( float fsize ) { g_class_size[ this.index ] = fsize; }
	}
	property float sizeinc
	{
		public get() { return g_class_size_inc[ this.index ]; }
		public set( float fsizeinc ) { g_class_size_inc[ this.index ] = fsizeinc; }
	}
	
	property float damage
	{
		public get() { return g_class_damage[ this.index ]; }
		public set( float fdamage ) { g_class_damage[ this.index ] = fdamage; }
	}
	property float damageinc
	{
		public get() { return g_class_damage_inc[ this.index ]; }
		public set( float fdamageinc ) { g_class_damage_inc[ this.index ] = fdamageinc; }
	}
	
	property float speed
	{
		public get() { return g_class_speed[ this.index ]; }
		public set( float fspeed ) { g_class_speed[ this.index ] = fspeed; }
	}
	property float speedinc
	{
		public get() { return g_class_speed_inc[ this.index ]; }
		public set( float fspeedinc ) { g_class_speed_inc[ this.index ] = fspeedinc; }
	}
	
	property float turnrate
	{
		public get() { return g_class_turnrate[ this.index ]; }
		public set( float fturnrate ) { g_class_turnrate[ this.index ] = fturnrate; }
	}
	property float turnrateinc
	{
		public get() { return g_class_turnrate_inc[ this.index ]; }
		public set( float fturnrateinc ) { g_class_turnrate_inc[ this.index ] = fturnrateinc; }
	}
	property float deflectdelay
	{
		public get() { return g_class_deflect_delay[ this.index ]; }
		public set( float delay ) { g_class_deflect_delay[ this.index ] = delay; }
	}
	property bool targetclosest
	{
		public get() { return g_class_target_closest[ this.index ]; }
		public set( bool tClosest ) { g_class_target_closest[ this.index ] = tClosest; }
	}
	property bool allowaimed
	{
		public get() { return g_class_aimed_allow[ this.index ]; }
		public set( bool allow ) { g_class_aimed_allow[ this.index ] = allow; }
	}
	property float aimedspeed
	{
		public get() { return g_class_aimed_speed[ this.index ]; }
		public set( float faimedspeed ) { g_class_aimed_speed[ this.index ] = faimedspeed; }
	}
	property int maxbounce
	{
		public get() { return g_class_bounce_max[ this.index ]; }
		public set( int ent ) { g_class_bounce_max[ this.index ] = ent; }
	}
	property float bouncedelay
	{
		public get() { return g_class_bounce_delay[ this.index ]; }
		public set( float delay ) { g_class_bounce_delay[ this.index ] = delay; }
	}
	
	//Sounds
	property bool snd_spawn_use
	{
		public get() { return g_class_sound_spawn_play[ this.index ]; }
		public set( bool allow ) { g_class_sound_spawn_play[ this.index ] = allow; }
	}
	public void GetSndSpawn(char [] sound, int length) { strcopy(sound, length, g_class_sound_spawn[this.index]); }
	public void SetSndSpawn(char [] sound) { strcopy(g_class_sound_spawn[this.index], PLATFORM_MAX_PATH, sound); }
	
	property bool snd_alert_use
	{
		public get() { return g_class_sound_alert_play[ this.index ]; }
		public set( bool allow ) { g_class_sound_alert_play[ this.index ] = allow; }
	}
	public void GetSndAlert(char [] sound, int length) { strcopy(sound, length, g_class_sound_alert[this.index]); }
	public void SetSndAlert(char [] sound) { strcopy(g_class_sound_alert[this.index], PLATFORM_MAX_PATH, sound); }
	
	property bool snd_deflect_use
	{
		public get() { return g_class_sound_deflect_play[ this.index ]; }
		public set( bool allow ) { g_class_sound_deflect_play[ this.index ] = allow; }
	}
	public void GetSndDeflectBlue(char [] sound, int length) { strcopy(sound, length, g_class_sound_deflect_red[this.index]); }
	public void SetSndDeflectBlue(char [] sound) { strcopy(g_class_sound_deflect_red[this.index], PLATFORM_MAX_PATH, sound); }
	
	public void GetSndDeflectRed(char [] sound, int length) { strcopy(sound, length, g_class_sound_deflect_blue[this.index]); }
	public void SetSndDeflectRed(char [] sound) { strcopy(g_class_sound_deflect_blue[this.index], PLATFORM_MAX_PATH, sound); }
	
	property bool snd_beep_use
	{
		public get() { return g_class_sound_beep_play[ this.index ]; }
		public set( bool allow ) { g_class_sound_beep_play[ this.index ] = allow; }
	}
	public void GetSndBeep(char [] sound, int length) { strcopy(sound, length, g_class_sound_beep[this.index]); }
	public void SetSndBeep(char [] sound) { strcopy(g_class_sound_beep[this.index], PLATFORM_MAX_PATH, sound); }
	property float snd_beep_delay
	{
		public get() { return g_class_sound_beep_interval[ this.index ]; }
		public set( float delay ) { g_class_sound_beep_interval[ this.index ] = delay; }
	}
	
	property bool snd_aimed_use
	{
		public get() { return g_class_sound_aimed_play[ this.index ]; }
		public set( bool allow ) { g_class_sound_aimed_play[ this.index ] = allow; }
	}
	public void GetSndAimed(char [] sound, int length) { strcopy(sound, length, g_class_sound_aimed[this.index]); }
	public void SetSndAimed(char [] sound) { strcopy(g_class_sound_aimed[this.index], PLATFORM_MAX_PATH, sound); }
	
	property bool snd_bounce_use
	{
		public get() { return g_class_sound_bounce_play[ this.index ]; }
		public set( bool allow ) { g_class_sound_bounce_play[ this.index ] = allow; }
	}
	public void GetSndBounce(char [] sound, int length) { strcopy(sound, length, g_class_sound_bounce[this.index]); }
	public void SetSndBounce(char [] sound) { strcopy(g_class_sound_bounce[this.index], PLATFORM_MAX_PATH, sound); }
	
	//Explosion
	property bool exp_use
	{
		public get() { return g_class_explosion_create[ this.index ]; }
		public set( bool allow ) { g_class_explosion_create[ this.index ] = allow; }
	}
	property float exp_damage
	{
		public get() { return g_class_explosion_damage[ this.index ]; }
		public set( float ent ) { g_class_explosion_damage[ this.index ] = ent; }
	}
	property float exp_push
	{
		public get() { return g_class_explosion_push_strength[ this.index ]; }
		public set( float ent ) { g_class_explosion_push_strength[ this.index ] = ent; }
	}
	property float exp_radius
	{
		public get() { return g_class_explosion_radius[ this.index ]; }
		public set( float ent ) { g_class_explosion_radius[ this.index ] = ent; }
	}
	property float exp_fallof
	{
		public get() { return g_class_explosion_fallof_radius[ this.index ]; }
		public set( float ent ) { g_class_explosion_fallof_radius[ this.index ] = ent; }
	}
	public void GetExpSound(char [] sound, int length) { strcopy(sound, length, g_class_explosion_sound[this.index]); }
	public void SetExpSound(char [] sound) { strcopy(g_class_explosion_sound[this.index], PLATFORM_MAX_PATH, sound); }

	
}
