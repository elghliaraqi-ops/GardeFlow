-- Trigger-only function: keep it unavailable through the Data API/RPC surface.
revoke execute on function public.enforce_exchange_promotion_scope() from public, anon, authenticated;
