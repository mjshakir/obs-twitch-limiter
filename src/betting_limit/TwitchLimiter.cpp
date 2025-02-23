#include "TwitchLimiter.hpp"
#include "eventsub.hpp"
#include <obs.h>
#include <obs-module.h>
#include <obs-properties.h>
#include <thread>
#include <chrono>
#include <string>

constexpr size_t DEFAULT_MAX_BET_LIMIT = 5000UL;
constexpr size_t DEFAULT_BET_TIMEOUT = 30UL;

// Implementation of the TwitchLimiter singleton
TwitchLimiter &TwitchLimiter::instance(void)
{
	static TwitchLimiter instance;
	return instance;
}

TwitchLimiter::TwitchLimiter(void)
	: m_initialized(initialize()),
	  m_custom_bet_limit_enabled(true),
	  m_io_context(),
	  m_reconnect_timer(m_io_context),
	  m_overlay_source(nullptr, &obs_source_release)
{
	m_work_guard.emplace(m_io_context.get_executor());
}

TwitchLimiter::~TwitchLimiter(void)
{
	shutdown();
}

// Example implementations of plugin methods:
bool TwitchLimiter::initialize(void)
{
	blog(LOG_INFO, "Twitch Betting Limit Plugin Loaded.");
	EventSub::instance().set_status_callback([this](bool connected) { update_websocket_status(connected); });

	EventSub::instance().set_overlay_callback(
		[this](std::string_view msg, size_t duration) { this->show_overlay_notification(msg, duration); });

	EventSub::instance().initialize();
	return true;
}

void TwitchLimiter::shutdown(void)
{
	hide_overlay_notification();
	EventSub::instance().shutdown();
}

bool TwitchLimiter::initialized(void) const
{
	return m_initialized;
}

obs_properties_t *TwitchLimiter::get_settings(void *data)
{
	static_cast<void>(data);
	std::unique_ptr<obs_properties_t, decltype(&obs_properties_destroy)> props(obs_properties_create(),
										   &obs_properties_destroy);

	// Add a boolean property for enabling/disabling the custom bet limit.
	obs_property_t *limit_toggle =
		obs_properties_add_bool(props.get(), "enable_custom_bet_limit", "Enable Custom Bet Limit");
	obs_property_set_modified_callback(
		limit_toggle, [](obs_properties_t *props, obs_property_t *prop, obs_data_t *data) -> bool {
			return TwitchLimiter::instance().toggle_custom_bet_limit(props, prop, data);
		});

	// Add integer properties.
	obs_properties_add_int(props.get(), "max_bet_limit", "Max Bet Limit", 100, 100000, 100);
	obs_properties_add_int(props.get(), "bet_timeout_duration", "Bet Timeout Duration (seconds)", 5, 300, 5);

	// Add button property for resetting bet limit.
	obs_properties_add_button(props.get(), "reset_bet_limit", "Reset Bet Limit",
				  [](obs_properties_t *props, obs_property_t *prop, void *data) -> bool {
					  return TwitchLimiter::instance().reset_bet_limit(
						  props, prop, static_cast<obs_data_t *>(data));
				  });

	// Add button property for resetting bet timeout.
	obs_properties_add_button(props.get(), "reset_bet_timeout", "Reset Bet Timeout",
				  [](obs_properties_t *props, obs_property_t *prop, void *data) -> bool {
					  return TwitchLimiter::instance().reset_bet_timeout(
						  props, prop, static_cast<obs_data_t *>(data));
				  });

	// Add button property for resetting the overlay.
	obs_properties_add_button(props.get(), "reset_overlay", "Reset Overlay",
				  [](obs_properties_t *props, obs_property_t *prop, void *data) -> bool {
					  return TwitchLimiter::instance().reset_overlay(props, prop, data);
				  });

	// Add text property for the WebSocket URL.
	obs_property_t *ws_url_prop =
		obs_properties_add_text(props.get(), "websocket_url", "WebSocket URL", OBS_TEXT_DEFAULT);
	obs_property_set_modified_callback(
		ws_url_prop, [](obs_properties_t *props, obs_property_t *prop, obs_data_t *data) -> bool {
			return TwitchLimiter::instance().validate_websocket_url(props, prop, data);
		});

	// Add button property to reset the WebSocket URL.
	obs_properties_add_button(props.get(), "reset_websocket_url", "Reset WebSocket URL",
				  [](obs_properties_t *props, obs_property_t *prop, void *data) -> bool {
					  return TwitchLimiter::instance().reset_websocket_url(
						  props, prop, static_cast<obs_data_t *>(data));
				  });

	// Add button property to manually reconnect to EventSub.
	obs_properties_add_button(props.get(), "manual_reconnect_eventsub", "Reconnect to Twitch EventSub",
				  [](obs_properties_t *props, obs_property_t *prop, void *data) -> bool {
					  return TwitchLimiter::instance().manual_reconnect_eventsub(
						  props, prop, static_cast<obs_data_t *>(data));
				  });

	// Add read-only text property for WebSocket status.
	obs_property_t *ws_status =
		obs_properties_add_text(props.get(), "ws_status", "WebSocket Status", OBS_TEXT_INFO);
	obs_property_set_enabled(ws_status, false);

	return props.release();
}

void TwitchLimiter::update_settings(obs_data_t *settings)
{
	m_custom_bet_limit_enabled.store(obs_data_get_bool(settings, "enable_custom_bet_limit"));
	EventSub::instance().set_max_bet_limit(m_custom_bet_limit_enabled.load(),
					       static_cast<size_t>(obs_data_get_int(settings, "max_bet_limit")));
	EventSub::instance().set_bet_timeout_duration(
		static_cast<size_t>(obs_data_get_int(settings, "bet_timeout_duration")));

	const char *new_url = obs_data_get_string(settings, "websocket_url");
	if (new_url && *new_url) {
		EventSub::instance().set_websocket_url(new_url);
	} else {
		EventSub::instance().set_websocket_url();
	}

	blog(LOG_INFO, "Updated WebSocket URL: %s", EventSub::instance().get_websocket_url().c_str());
	blog(LOG_INFO, "Updated Bet Limit: %s",
	     m_custom_bet_limit_enabled.load() ? std::to_string(EventSub::instance().get_max_bet_limit()).c_str()
					       : "Disabled");
	blog(LOG_INFO, "Updated Bet Timeout Duration: %zu seconds", EventSub::instance().get_bet_timeout_duration());
}

// The remaining functions (toggle, reset, etc.) can be implemented similarly
bool TwitchLimiter::toggle_custom_bet_limit(obs_properties_t *props, obs_property_t *prop, obs_data_t *data)
{
	(void)props;
	(void)prop;
	(void)data;
	m_custom_bet_limit_enabled.store(!m_custom_bet_limit_enabled.load());
	blog(LOG_INFO, "Custom Bet Limit %s", m_custom_bet_limit_enabled ? "Enabled" : "Disabled");
	return true;
}

bool TwitchLimiter::reset_bet_limit(obs_properties_t *props, obs_property_t *prop, obs_data_t *data)
{
	(void)props;
	(void)prop;
	EventSub::instance().set_max_bet_limit(DEFAULT_MAX_BET_LIMIT);
	update_settings(data);
	blog(LOG_INFO, "Reset Bet Limit to default: %ld", DEFAULT_MAX_BET_LIMIT);
	return true;
}

bool TwitchLimiter::reset_bet_timeout(obs_properties_t *props, obs_property_t *prop, obs_data_t *data)
{
	(void)props;
	(void)prop;
	EventSub::instance().set_bet_timeout_duration(DEFAULT_BET_TIMEOUT);
	update_settings(data);
	blog(LOG_INFO, "Reset Bet Timeout to default: %ld seconds", DEFAULT_BET_TIMEOUT);
	return true;
}

bool TwitchLimiter::manual_reconnect_eventsub(obs_properties_t *props, obs_property_t *prop, obs_data_t *data)
{
	(void)props;
	(void)prop;
	(void)data;
	blog(LOG_INFO, "Manually reconnecting to Twitch EventSub...");
	EventSub::instance().shutdown();
	EventSub::instance().initialize();
	return true;
}

bool TwitchLimiter::reset_websocket_url(obs_properties_t *props, obs_property_t *prop, obs_data_t *data)
{
	(void)props;
	(void)prop;
	(void)data;
	EventSub::instance().set_websocket_url();
	blog(LOG_INFO, "WebSocket URL reset to default: %s", EventSub::instance().get_websocket_url().c_str());
	return true;
}

bool TwitchLimiter::validate_websocket_url(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings)
{
	(void)props;
	(void)prop;
	const char *new_url = obs_data_get_string(settings, "websocket_url");
	if (new_url && *new_url) {
		EventSub::instance().set_websocket_url(new_url);
		blog(LOG_INFO, "WebSocket URL updated: %s", EventSub::instance().get_websocket_url().c_str());
	}
	return true;
}

bool TwitchLimiter::reset_overlay(obs_properties_t *props, obs_property_t *prop, void *data)
{
	static_cast<void>(props);
	static_cast<void>(prop);
	static_cast<void>(data);
	hide_overlay_notification();
	blog(LOG_INFO, "Overlay manually reset by user.");
	return true;
}

void TwitchLimiter::show_overlay_notification(std::string_view message, size_t duration)
{
	std::unique_ptr<obs_data_t, decltype(&obs_data_release)> settings(obs_data_create(), &obs_data_release);
	obs_data_set_string(settings.get(), "text", message.data());

	if (!m_overlay_source) {
		m_overlay_source.reset(obs_source_create("text_gdiplus", "Bet Limit Warning", settings.get(), nullptr));
	} else {
		obs_source_update(m_overlay_source.get(), settings.get());
	}

	// Set timer to auto-hide overlay
	m_reconnect_timer.expires_after(std::chrono::seconds(duration));
	m_reconnect_timer.async_wait([this](const boost::system::error_code &) { this->hide_overlay_notification(); });

	// Start Boost.Asio event loop in background
	std::thread([this]() { m_io_context.run(); }).detach();
}

void TwitchLimiter::hide_overlay_notification(void)
{
	m_work_guard.reset(); // Smart pointer handles cleanup
	m_reconnect_timer.cancel();
}

void TwitchLimiter::update_websocket_status(bool connected) const
{
	obs_data_t *settings = obs_data_create();
	obs_data_set_string(settings, "ws_status", connected ? "Connected ✅" : "Disconnected ❌");

	// OBS Logging (for debugging and logs)
	blog(LOG_INFO, "WebSocket Status: %s", connected ? "Connected to Twitch EventSub!" : "WebSocket Disconnected!");
}
