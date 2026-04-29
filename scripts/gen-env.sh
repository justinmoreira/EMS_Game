#!/usr/bin/env bash
# Generates client/.env from the running local Supabase instance

CLIENT_PATH="${CLIENT_PATH:-client}"

PUBLIC_SUPABASE_URL=$(supabase status --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['API_URL'])" 2>/dev/null)
SUPABASE_KEY=$(supabase status --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['ANON_KEY'])" 2>/dev/null)

if [ -n "$PUBLIC_SUPABASE_URL" ] && [ -n "$SUPABASE_KEY" ]; then
    echo "PUBLIC_SUPABASE_URL=$PUBLIC_SUPABASE_URL" > "$CLIENT_PATH/.env"
    echo "PUBLIC_SUPABASE_ANON_KEY=$SUPABASE_KEY" >> "$CLIENT_PATH/.env"
    echo "🔑 Supabase env written to $CLIENT_PATH/.env"
else
    echo "⚠️  Supabase not running — $CLIENT_PATH/.env not generated. Run 'just db-start' first."
    exit 1
fi
