/*
 * Jetpack
 * by: shanapu
 * original by: FrozDark & gubka
 * https://github.com/shanapu/
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */

/******************************************************************************
                   STARTUP
******************************************************************************/

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

ConVar gc_bEnable;
ConVar gc_bAdminsOnly;
ConVar gc_bAdminsUnlimited;
ConVar gc_sAdminFlag;
ConVar gc_iTeam;
ConVar gc_fReloadDelay;
ConVar gc_fJetPackBoost;
ConVar gc_fJetPackMax;
ConVar gc_iJetPackAngle;
ConVar gc_bCommand;

bool g_bDelay[MAXPLAYERS+1];
bool g_bIsAdmin[MAXPLAYERS+1];

Handle g_hTimer[MAXPLAYERS+1];

int g_iJumps[MAXPLAYERS+1];
int g_iFirstSpawn[MAXPLAYERS+1] = false;

char g_sAdminFlag[64];

public Plugin myinfo =
{
	name = "Jetpack for CSGO",
	author = "shanapu, FrozDark & gubka",
	description = "A jetpack for csgo without need of zombie",
	version = "1.1",
	url = "https://github.com/shanapu"
};

public void OnPluginStart()
{
	RegConsoleCmd("+jetpack", Command_JetpackON);
	RegConsoleCmd("-jetpack", Command_JetpackOFF);

	gc_bEnable = CreateConVar("sm_jetpack_enabled", "1", "Enables JetPack.", _, true, 0.0, true, 1.0);
	gc_bCommand = CreateConVar("sm_jetpack_cmd", "0", "0 - DUCK & JUMP, 1 - +/-jetpack", _, true, 0.0, true, 1.0);
	gc_bAdminsOnly = CreateConVar("sm_jetpack_admins_only", "0", "Only admins will be able to use JetPack.", _, true, 0.0, true, 1.0);
	gc_bAdminsUnlimited = CreateConVar("sm_jetpack_admins_unlimited", "0", "Allow admins to have unlimited JetPack.", _, true, 0.0, true, 1.0);
	gc_sAdminFlag = CreateConVar("sm_jetpack_admins_flag", "b,r", "Admin flag to access to the JetPack.");
	gc_iTeam = CreateConVar("sm_jetpack_team", "3", "Which team should have access to jetpack? 1 - CT only / 2- T only / 3 - both", _, true, 1.0, true, 3.0);
	gc_fReloadDelay = CreateConVar("sm_jetpack_reloadtime", "60", "Time in seconds to reload JetPack.", _, true, 1.0);
	gc_fJetPackBoost = CreateConVar("sm_jetpack_boost", "400.0", "The amount of boost to apply to JetPack.", _, true, 100.0);
	gc_iJetPackAngle = CreateConVar("sm_jetpack_angle", "50", "The angle of boost to apply to JetPack.", _, true, 10.0, true, 80.0);
	gc_fJetPackMax = CreateConVar("sm_jetpack_max", "10", "Time in seconds of using JetPacks.", _, true, 0.0);

	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_spawn", OnPlayerSpawn);

	AutoExecConfig(true, "JetPack");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientAuthorized(client))
			OnClientPostAdminCheck(client);
	}

	HookConVarChange(gc_sAdminFlag, OnSettingChanged);

	gc_sAdminFlag.GetString(g_sAdminFlag, sizeof(g_sAdminFlag));
}

public void OnSettingChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (convar == gc_sAdminFlag)
	{
		strcopy(g_sAdminFlag, sizeof(g_sAdminFlag), newValue);
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (CheckVipFlag(client, g_sAdminFlag))
	{
		g_bIsAdmin[client] = true;
	}
	else g_bIsAdmin[client] = false;

	g_iFirstSpawn[client] = false;
}

public void OnClientDisconnect_Post(int client)
{
	g_iJumps[client] = 0;
	g_bDelay[client] = false;

	if (g_hTimer[client] != INVALID_HANDLE)
	{
		KillTimer(g_hTimer[client]);
		g_hTimer[client] = INVALID_HANDLE;
	}
}

public void OnPlayerDeath(Handle event, const char [] name, bool dontBroadcast)
{
	if (!gc_bEnable.BoolValue)
		return;

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_bDelay[client])
		OnClientDisconnect_Post(client);
}

public void OnPlayerSpawn(Handle event, const char [] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (g_iFirstSpawn[client])
		return;

	g_iFirstSpawn[client] = true;

	PrintToChat(client, "Jetpack is enabled: to use", gc_bCommand.BoolValue?"bind +jetpack":"press CTRL + SPACE (duck+jump)");
}

Handle Timer_Client[MAXPLAYERS+1];

public Action Command_JetpackON(int client, int args)
{
	if (gc_bCommand.BoolValue)
	{
		Timer_Client[client] = CreateTimer(0.1, Timer_Fly, client, TIMER_REPEAT);
	}
}

public Action Command_JetpackOFF(int client, int args)
{
	if (Timer_Client[client] != null)
	{
		CloseHandle(Timer_Client[client]);
	}
	Timer_Client[client] = null;
}


public Action Timer_Fly(Handle tmr, int client)
{
	if (!gc_bEnable.BoolValue || !IsClientConnected(client) || g_bDelay[client] || (gc_bAdminsOnly.BoolValue && !g_bIsAdmin[client]))
		return Plugin_Handled;

	if ((GetClientTeam(client) != CS_TEAM_CT && gc_iTeam.IntValue == 1) || (GetClientTeam(client) != CS_TEAM_T && gc_iTeam.IntValue == 2) || !IsPlayerAlive(client))
		return Plugin_Handled;

	if (0 <= g_iJumps[client] <= gc_fJetPackMax.IntValue)
	{
		if (gc_fJetPackMax.IntValue)
		{
			if (g_bIsAdmin[client])
			{
				if (!gc_bAdminsUnlimited.BoolValue)
					g_iJumps[client]++;
			}
			else
				g_iJumps[client]++;
		}

		float ClientEyeAngle[3];
		float ClientAbsOrigin[3];
		float Velocity[3];

		GetClientEyeAngles(client, ClientEyeAngle);
		GetClientAbsOrigin(client, ClientAbsOrigin);

		float newAngle = gc_iJetPackAngle.FloatValue * -1.0;
		ClientEyeAngle[0] = newAngle;
		GetAngleVectors(ClientEyeAngle, Velocity, NULL_VECTOR, NULL_VECTOR);

		ScaleVector(Velocity, gc_fJetPackBoost.FloatValue);

		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, Velocity);

		g_bDelay[client] = true;
		CreateTimer(0.1, DelayOff, client);

		CreateEffect(client, ClientAbsOrigin, ClientEyeAngle);

		if (g_iJumps[client] == gc_fJetPackMax.IntValue && gc_fReloadDelay.FloatValue)
		{
			if (Timer_Client[client] != null)
			{
				CloseHandle(Timer_Client[client]);
			}
			Timer_Client[client] = null;
			g_hTimer[client] = CreateTimer(gc_fReloadDelay.FloatValue, Reload, client);
			PrintCenterText(client, "Jetpack Empty");
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}


public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (gc_bCommand.BoolValue)
		return Plugin_Continue;

	if (!gc_bEnable.BoolValue || !IsPlayerAlive(client) || g_bDelay[client] || (gc_bAdminsOnly.BoolValue && !g_bIsAdmin[client]))
		return Plugin_Continue;

	if ((GetClientTeam(client) != CS_TEAM_CT && gc_iTeam.IntValue == 1) || (GetClientTeam(client) != CS_TEAM_T && gc_iTeam.IntValue == 2))
		return Plugin_Continue;

	if (buttons & IN_JUMP && buttons & IN_DUCK)
	{
		if (0 <= g_iJumps[client] <= gc_fJetPackMax.IntValue)
		{
			if (gc_fJetPackMax.IntValue)
			{
				if (g_bIsAdmin[client])
				{
					if (!gc_bAdminsUnlimited.BoolValue)
						g_iJumps[client]++;
				}
				else
					g_iJumps[client]++;
			}

			float ClientEyeAngle[3];
			float ClientAbsOrigin[3];
			float Velocity[3];

			GetClientEyeAngles(client, ClientEyeAngle);
			GetClientAbsOrigin(client, ClientAbsOrigin);

			float newAngle = gc_iJetPackAngle.FloatValue * -1.0;
			ClientEyeAngle[0] = newAngle;
			GetAngleVectors(ClientEyeAngle, Velocity, NULL_VECTOR, NULL_VECTOR);

			ScaleVector(Velocity, gc_fJetPackBoost.FloatValue);

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, Velocity);

			g_bDelay[client] = true;
			CreateTimer(0.1, DelayOff, client);

			CreateEffect(client, ClientAbsOrigin, ClientEyeAngle);

			if (g_iJumps[client] == gc_fJetPackMax.IntValue && gc_fReloadDelay.FloatValue)
			{
				g_hTimer[client] = CreateTimer(gc_fReloadDelay.FloatValue, Reload, client);
				PrintCenterText(client, "Jetpack Empty");
			}
		}
	}
	return Plugin_Continue;
}

void CreateEffect(int client, float vecorigin[3], float vecangle[3])
{
	vecangle[0] = 110.0;
	vecorigin[2] += 25.0;

	char tName[128];
	Format(tName, sizeof(tName), "target%i", client);
	DispatchKeyValue(client, "targetname", tName);

	// Create the fire
	char fire_name[128];
	Format(fire_name, sizeof(fire_name), "fire%i", client);
	int fire = CreateEntityByName("env_steam");
	DispatchKeyValue(fire,"targetname", fire_name);
	DispatchKeyValue(fire, "parentname", tName);
	DispatchKeyValue(fire,"SpawnFlags", "1");
	DispatchKeyValue(fire,"Type", "0");
	DispatchKeyValue(fire,"InitialState", "1");
	DispatchKeyValue(fire,"Spreadspeed", "10");
	DispatchKeyValue(fire,"Speed", "400");
	DispatchKeyValue(fire,"Startsize", "20");
	DispatchKeyValue(fire,"EndSize", "600");
	DispatchKeyValue(fire,"Rate", "30");
	DispatchKeyValue(fire,"JetLength", "200");
	DispatchKeyValue(fire,"RenderColor", "255 100 30");
	DispatchKeyValue(fire,"RenderAmt", "180");
	DispatchSpawn(fire);

	TeleportEntity(fire, vecorigin, vecangle, NULL_VECTOR);
	SetVariantString(tName);
	AcceptEntityInput(fire, "SetParent", fire, fire, 0);

	AcceptEntityInput(fire, "TurnOn");

	char fire_name2[128];
	Format(fire_name2, sizeof(fire_name2), "fire2%i", client);
	int fire2 = CreateEntityByName("env_steam");
	DispatchKeyValue(fire2,"targetname", fire_name2);
	DispatchKeyValue(fire2, "parentname", tName);
	DispatchKeyValue(fire2,"SpawnFlags", "1");
	DispatchKeyValue(fire2,"Type", "1");
	DispatchKeyValue(fire2,"InitialState", "1");
	DispatchKeyValue(fire2,"Spreadspeed", "10");
	DispatchKeyValue(fire2,"Speed", "400");
	DispatchKeyValue(fire2,"Startsize", "20");
	DispatchKeyValue(fire2,"EndSize", "600");
	DispatchKeyValue(fire2,"Rate", "10");
	DispatchKeyValue(fire2,"JetLength", "200");
	DispatchSpawn(fire2);
	TeleportEntity(fire2, vecorigin, vecangle, NULL_VECTOR);
	SetVariantString(tName);
	AcceptEntityInput(fire2, "SetParent", fire2, fire2, 0);
	AcceptEntityInput(fire2, "TurnOn");

	Handle firedata = CreateDataPack();
	WritePackCell(firedata, fire);
	WritePackCell(firedata, fire2);
	CreateTimer(0.5, Killfire, firedata);
}

public Action Killfire(Handle timer, Handle firedata)
{
	ResetPack(firedata);
	int ent1 = ReadPackCell(firedata);
	int ent2 = ReadPackCell(firedata);
	CloseHandle(firedata);

	char classname[256];

	if (IsValidEntity(ent1))
	{
		AcceptEntityInput(ent1, "TurnOff");
		GetEdictClassname(ent1, classname, sizeof(classname));
		if (!strcmp(classname, "env_steam", false))
			AcceptEntityInput(ent1, "kill");
	}

	if (IsValidEntity(ent2))
	{
		AcceptEntityInput(ent2, "TurnOff");
		GetEdictClassname(ent2, classname, sizeof(classname));
		if (StrEqual(classname, "env_steam", false))
			AcceptEntityInput(ent2, "kill");
	}
}

public Action DelayOff(Handle timer, any client)
{
	g_bDelay[client] = false;
}

public Action Reload(Handle timer, any client)
{
	if (g_hTimer[client] != INVALID_HANDLE)
	{
		g_iJumps[client] = 0;
		PrintCenterText(client, "Jetpack Reloaded");
		g_hTimer[client] = INVALID_HANDLE;
	}
}

bool CheckVipFlag(int client, char [] flagsNeed)
{
	int iCount = 0;
	char sflagNeed[22][8], sflagFormat[64];
	bool bEntitled = false;

	Format(sflagFormat, sizeof(sflagFormat), flagsNeed);
	ReplaceString(sflagFormat, sizeof(sflagFormat), " ", "");
	iCount = ExplodeString(sflagFormat, ",", sflagNeed, sizeof(sflagNeed), sizeof(sflagNeed[]));

	for (int i = 0; i < iCount; i++)
	{
		if ((GetUserFlagBits(client) & ReadFlagString(sflagNeed[i]) == ReadFlagString(sflagNeed[i])) || (GetUserFlagBits(client) & ADMFLAG_ROOT))
		{
			bEntitled = true;
			break;
		}
	}

	return bEntitled;
}