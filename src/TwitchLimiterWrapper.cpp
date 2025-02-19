#include "TwitchLimiterWrapper.h"
#include "TwitchLimiter.hpp"

extern "C" {

bool TwitchLimiter_load(void)
{
    return TwitchLimiter::instance().initialized();
}

void TwitchLimiter_unload(void)
{
    TwitchLimiter::instance().shutdown();
}

obs_properties_t *TwitchLimiter_get_settings(void *data)
{
    return TwitchLimiter::instance().get_settings(data);
}

void TwitchLimiter_update_settings(obs_data_t *settings)
{
    TwitchLimiter::instance().update_settings(settings);
}

} // extern "C"
