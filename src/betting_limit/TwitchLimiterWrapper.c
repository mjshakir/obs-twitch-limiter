#include "TwitchLimiterWrapper.h"
#include "TwitchLimiter.hpp"


extern "C" {

    bool TwitchLimiter_load(void)
    {
        #ifdef __cplusplus
            return TwitchLimiter_load_cpp();
        #else
            return false;
        #endif
    }
    
    void TwitchLimiter_unload(void)
    {
        #ifdef __cplusplus
            TwitchLimiter_unload_cpp();
        #endif
    }
    
    obs_properties_t *TwitchLimiter_get_settings(void *data)
    {
        #ifdef __cplusplus
            return TwitchLimiter_get_settings_cpp(data);
        #else
            return NULL;
        #endif
    }
    
    void TwitchLimiter_update_settings(obs_data_t *settings)
    {
        #ifdef __cplusplus
            TwitchLimiter_update_settings_cpp(settings);
        #endif
    }

} // extern "C"
