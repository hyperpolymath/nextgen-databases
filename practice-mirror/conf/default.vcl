# conf/default.vcl
# Varnish Cache Configuration for WordPress

vcl 4.1;

import std;
import http;

# Default backend for OpenLiteSpeed
backend default {
    .host = "127.0.0.1"; # OpenLiteSpeed is on the same container
    .port = "8080";      # OpenLiteSpeed's default port
    .connect_timeout = 5s;
    .first_byte_timeout = 15s;
    .between_bytes_timeout = 10s;
}

sub vcl_recv {
    # Don't cache if backend request contains these headers
    if (req.http.Authorization || req.http.Cookie) {
        return (pass);
    }

    # Don't cache POST requests
    if (req.method == "POST") {
        return (pass);
    }

    # Don't cache WordPress admin area and login pages
    if (req.url ~ "^/wp-admin/" || req.url ~ "^/wp-login.php") {
        return (pass);
    }

    # Remove has_js from querystring
    if (req.url ~ "(\?|&)(has_js|g_event)=\w+") {
        set req.url = std.querysort(req.url);
        set req.url = regsuball(req.url, "&(has_js|g_event)=\w+", "");
        set req.url = regsuball(req.url, "\?(has_js|g_event)=\w+&?", "?");
        set req.url = regsub(req.url, "\?$", "");
    }

    # Allow serving stale content if backend is down
    set req.grace = 1h;

    return (hash);
}

sub vcl_backend_response {
    # Don't cache if backend sends these headers
    if (beresp.http.Set-Cookie || beresp.http.Vary ~ "Cookie") {
        return (deliver);
    }

    # Cache all static files for 1 day
    if (beresp.ttl < 0s || beresp.http.Cache-Control ~ "(no-cache|no-store|private)") {
        # Do not cache by default if explicitly told not to or not cacheable
        return (deliver);
    } else if (beresp.http.Content-Type ~ "(text/css|application/javascript|image/jpeg|image/png|image/gif|image/x-icon|image/svg\+xml|image/webp)") {
        set beresp.ttl = 1d;
    } else {
        # Default cache for other content for 1 hour
        set beresp.ttl = 1h;
    }

    return (deliver);
}

sub vcl_deliver {
    # Remove some headers from delivery for security/cleanliness
    unset resp.http.X-Powered-By;
    unset resp.http.X-Varnish;
    unset resp.http.Via;
    unset resp.http.Server; # OpenLiteSpeed will be here.
}
