#pragma once

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>
#include <atomic>
#include <optional>
#include <boost/asio/io_context.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/executor_work_guard.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/websocket.hpp>
#include <boost/system/error_code.hpp>

class EventSub {
public:
	static EventSub &instance(void); // Singleton instance

	void initialize(void) const;
	void shutdown(void) const;

	void set_max_bet_limit(const size_t &limit);
	void set_bet_timeout_duration(const size_t &duration);

	void set_overlay_callback(std::function<void(std::string_view, size_t)> callback);
	void set_status_callback(std::function<void(bool)> callback);

protected:
	EventSub(void);
	~EventSub(void);
	EventSub(const EventSub &) = delete;
	EventSub(EventSub &&) = delete;

	void async_connect(void) const;
	void async_listenForBets(void) const;

	void notify_status(bool connected);
	void notify_overlay(std::string_view message, size_t duration) const;

	void handle_resolve(const boost::system::error_code &ec,
			    boost::asio::ip::tcp::resolver::results_type results) const;
	void handle_connect(const boost::system::error_code &ec);
	void handle_read(const boost::system::error_code &ec, const size_t &bytes_transferred,
			 boost::beast::flat_buffer &buffer) const;

	void check_connection_status(const boost::system::error_code &ec) const;

private:
	std::atomic<bool> m_connected;
	std::atomic<size_t> m_max_bet_limit, m_bet_timeout_duration, m_reconnect_attempts;
	std::string m_websocket_url;
	boost::asio::io_context m_io_context;
	boost::asio::ip::tcp::resolver m_resolver;
	boost::beast::websocket::stream<boost::asio::ip::tcp::socket> m_websocket;
	boost::asio::steady_timer m_reconnect_timer;
	boost::beast::flat_buffer m_buffer;
	std::optional<boost::asio::executor_work_guard<boost::asio::io_context::executor_type>> m_work_guard;

	std::function<void(std::string_view, size_t)> m_overlay_callback;
	std::function<void(bool)> m_status_callback;
};
