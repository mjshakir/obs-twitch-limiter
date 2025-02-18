#pragma once

#include <cstddef>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <atomic>
#include <optional>

namespace boost {
namespace asio {
class io_context;
namespace ip {
class tcp;
}
class steady_timer;
namespace ssl {
class context;
}
class excutor_work_guard;
} // namespace asio
namespace beast {
class flat_buffer;
namespace websocket {
template<typename T> class stream;
}
} // namespace beast
namespace system {
class error_code;
}
} // namespace boost

class EventSub {
public:
	static EventSub &instance(void); // Singleton instance

	void initialize(void);
	void shutdown(void);

	void set_max_bet_limit(const size_t &limit);
	void set_bet_timeout_duration(const size_t &duration);

	void set_overlay_callback(std::function<void(std::string_view, size_t)> callback);
	void set_status_callback(std::function<void(bool)> callback);

protected:
	EventSub(void);
	~EventSub(void);

	void async_connect(void);
	void async_listenForBets(void);

	void notify_overlay(std::string_view message, size_t duration);
	void notify_status(bool connected);

	void handle_resolve(const boost::system::error_code &ec, boost::asio::ip::tcp::resolver::results_type results);
	void handle_connect(const boost::system::error_code &ec);
	void handle_read(const boost::system::error_code &ec, const size_t &bytes_transferred,
			 boost::beast::flat_buffer &buffer);

	void check_connection_status(const boost::system::error_code &ec);

private:
	std::atomic<bool> m_connected;
	std::atomic<size_t> m_max_bet_limit, m_bet_timeout_duration, m_reconnect_attempts;
	std::string m_websocket_url;
	std::unique_ptr<boost::asio::io_context> m_io_context;
	std::unique_ptr<boost::asio::ip::tcp::resolver> m_resolver;
	std::unique_ptr<boost::beast::websocket::stream<boost::asio::ip::tcp::socket>> m_websocket;
	std::unique_ptr<boost::asio::steady_timer> m_reconnect_timer;
	std::unique_ptr<boost::beast::flat_buffer> m_buffer;
	std::optional<boost::asio::executor_work_guard<boost::asio::io_context::executor_type>> m_work_guard;

	std::function<void(std::string_view, size_t)> m_overlay_callback;
	std::function<void(bool)> m_status_callback;
};
