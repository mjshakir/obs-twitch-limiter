#pragma once

#include <obs-module.h>
#include <string>
#include <string_view>
#include <cstddef>
#include <atomic>
#include <optional>
#include <memory>

#include <boost/asio.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/executor_work_guard.hpp>

class TwitchLimiter {
public:
	// Singleton access
	static TwitchLimiter &instance(void);

	// C++ methods that implement plugin functionality
	bool initialize(void) const;
	void shutdown(void) const;
	bool initialized(void) const;
	obs_properties_t *get_settings(void *data) const;
	void update_settings(obs_data_t *settings);

	// OBS UI callback implementations
	bool toggle_custom_bet_limit(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings);
	bool reset_bet_limit(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings);
	bool reset_bet_timeout(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings);
	bool manual_reconnect_eventsub(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings);
	bool reset_websocket_url(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings);
	bool validate_websocket_url(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings);

	void show_overlay_notification(std::string_view message, size_t duration);
	void hide_overlay_notification(void);
	bool reset_overlay(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings);

	bool valid_websocket_url(std::string_view url) const;
	void update_websocket_status(bool connected) const;

protected:
	TwitchLimiter(void);
	~TwitchLimiter(void);
	TwitchLimiter(const TwitchLimiter &) = delete;
	TwitchLimiter &operator=(const TwitchLimiter &) = delete;
	TwitchLimiter(TwitchLimiter &&) = delete;
	TwitchLimiter &operator=(TwitchLimiter &&) = delete;

private:
	// Member variables for settings, overlay, etc.
	const bool m_initialized;
	std::atomic<bool> m_custom_bet_limit_enabled;
	std::atomic<size_t> m_max_bet_limit;
	std::atomic<size_t> m_bet_timeout_duration;
	std::string m_websocket_url;
	boost::asio::io_context m_io_context;
	boost::asio::steady_timer m_reconnect_timer;
	std::optional<boost::asio::executor_work_guard<boost::asio::io_context::executor_type>> m_work_guard;
	std::unique_ptr<obs_source_t, decltype(&obs_source_release)> m_overlay_source;
};

#ifdef __cplusplus
extern "C" {
#endif

// OBS requires a C interface for the plugin entry points:
bool obs_module_load(void);
void obs_module_unload(void);
obs_properties_t *obs_module_get_settings(void *data);
void obs_module_update_settings(obs_data_t *settings);

#ifdef __cplusplus
}
#endif