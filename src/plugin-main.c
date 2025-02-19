/*
Plugin Name
Copyright (C) <Year> <Developer> <Email Address>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>
*/

#include <obs-module.h>
#include <plugin-support.h>
#include "TwitchLimiterWrapper.h"

bool obs_module_load(void);
void obs_module_unload(void);
obs_properties_t *obs_module_get_settings(void *data);
void obs_module_update_settings(obs_data_t *settings);

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("obs_twitch_plugin", "en-US")

bool obs_module_load(void)
{
	return TwitchLimiter_load();
}

void obs_module_unload(void)
{
	TwitchLimiter_unload();
}

obs_properties_t *obs_module_get_settings(void *data)
{
	return TwitchLimiter_get_settings(data);
}

void obs_module_update_settings(obs_data_t *settings)
{
	TwitchLimiter_update_settings(settings);
}

// Ensure there is a blank line at the end of this file.