#pragma once

#include <obs-module.h>
#include <string_view>

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("obs_twitch_plugin", "en-US")

bool obs_module_load(void);
void obs_module_unload(void);

// OBS Settings UI
obs_properties_t* obs_module_get_settings(void* data);
void obs_module_update_settings(obs_data_t* settings);
bool toggle_custom_bet_limit(obs_properties_t* props, obs_property_t* prop, void* data);
bool reset_bet_limit(obs_properties_t* props, obs_property_t* prop, void* data);
bool reset_bet_timeout(obs_properties_t* props, obs_property_t* prop, void* data);
bool manual_reconnect_eventsub(obs_properties_t* props, obs_property_t* prop, void* data);
bool reset_websocket_url(obs_properties_t* props, obs_property_t* prop, void* data);
bool validate_websocket_url(obs_properties_t* props, obs_property_t* prop, void* data);

void show_overlay_notification(std::string_view message, size_t duration);
void hide_overlay_notification(void);
bool reset_overlay(obs_properties_t* props, obs_property_t* prop, void* data);

bool valid_websocket_url(std::string_view url);
void update_websocket_status(bool is_connected);