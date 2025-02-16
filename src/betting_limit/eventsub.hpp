#pragma once

#include <cstddef>
#include <string_view>

class EventSub {
    public:
        static void initialize(void);
        static void shutdown(void);
        static void set_max_bet_limit(const size_t& limit);
        static void set_bet_timeout_duration(const size_t& duration);
        static void set_overlay_callback(std::function<void(std::string_view, size_t)> callback)
        static void set_status_callback(std::function<void(bool)> callback);
    protected:
        static void async_connect(void);
        static void async_listenForBets(void);
        void notify_overlay(std::string_view message, size_t duration);
        void notify_status(bool connected);
};