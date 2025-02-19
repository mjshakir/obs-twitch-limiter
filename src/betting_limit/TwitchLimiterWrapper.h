#pragma once

#include <obs-module.h>

#ifdef __cplusplus
extern "C" {
#endif

bool TwitchLimiter_load(void);
void TwitchLimiter_unload(void);
obs_properties_t *TwitchLimiter_get_settings(void *data);
void TwitchLimiter_update_settings(obs_data_t *settings);

#ifdef __cplusplus
}
#endif

// Ensure there is a blank line at the end of this file.