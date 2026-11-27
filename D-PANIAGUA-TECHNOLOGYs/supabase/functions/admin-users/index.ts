/// <reference types="https://deno.land/x/deno@v1.40.5/types.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Debes iniciar sesión." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const configuredSecretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  let serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (configuredSecretKeys) {
    try {
      serviceKey = JSON.parse(configuredSecretKeys)["default"] ?? serviceKey;
    } catch {
      return json({ error: "La configuración segura de Supabase no es válida." }, 500);
    }
  }
  if (!url || !serviceKey) return json({ error: "Faltan secretos de Supabase en la función." }, 500);

  const adminDb = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = authHeader.slice("Bearer ".length);
  const { data: authData, error: authError } = await adminDb.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Sesión no válida." }, 401);

  const callerId = authData.user.id;
  const { data: callerProfile, error: callerError } = await adminDb
    .from("profiles").select("role,is_active").eq("id", callerId).maybeSingle();
  if (callerError || callerProfile?.role !== "admin" || callerProfile?.is_active === false) return json({ error: "Acceso denegado: solo administradores activos." }, 403);

  let body: { action?: string; userId?: string; fullName?: string; role?: string; phone?: string; isActive?: boolean };
  try { body = await req.json(); } catch { return json({ error: "Solicitud JSON no válida." }, 400); }
  if (body.action === "list") {
    const authUsers: Array<{ id: string; email?: string; created_at: string }> = [];
    for (let page = 1; page <= 100; page++) {
      const { data, error } = await adminDb.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) return json({ error: "No se pudieron consultar los usuarios." }, 500);
      authUsers.push(...data.users.map((u) => ({ id: u.id, email: u.email, created_at: u.created_at })));
      if (data.users.length < 1000) break;
    }
    const [{ data: profiles, error: profileError }, { data: orders, error: orderError }] = await Promise.all([
      adminDb.from("profiles").select("id,full_name,phone,role,is_active,created_at"),
      adminDb.from("orders").select("user_id,total,status,payment_status"),
    ]);
    if (profileError || orderError) return json({ error: "No se pudieron cargar los datos de los usuarios." }, 500);
    const profileById = new Map((profiles ?? []).map((p) => [p.id, p]));
    const totals = new Map<string, { count: number; total: number }>();
    for (const order of orders ?? []) {
      const current = totals.get(order.user_id) ?? { count: 0, total: 0 };
      if (order.status !== "cancelled") {
        current.count += 1;
        if (order.payment_status === "confirmed") current.total += Number(order.total) || 0;
      }
      totals.set(order.user_id, current);
    }
    return json({ users: authUsers.map((authUser) => {
      const profile = profileById.get(authUser.id);
      const purchases = totals.get(authUser.id) ?? { count: 0, total: 0 };
      return {
        id: authUser.id,
        email: authUser.email ?? "",
        created_at: profile?.created_at ?? authUser.created_at,
        full_name: profile?.full_name ?? "",
        phone: profile?.phone ?? "",
        role: profile?.role ?? "customer",
        is_active: profile?.is_active ?? true,
        order_count: purchases.count,
        purchase_total: purchases.total,
      };
    }) });
  }
  const targetId = body.userId;
  if (!targetId || !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(targetId)) return json({ error: "Identificador de usuario no válido." }, 400);

  if (body.action === "update") {
    const fullName = String(body.fullName ?? "").trim();
    const role = String(body.role ?? "").trim();
    const phone = String(body.phone ?? "").trim().slice(0, 40);
    const isActive = body.isActive !== false;
    if (fullName.length < 2 || fullName.length > 120) return json({ error: "El nombre debe tener entre 2 y 120 caracteres." }, 400);
    if (!["admin", "customer"].includes(role)) return json({ error: "Rol no válido." }, 400);
    const { data: target, error: targetError } = await adminDb.from("profiles").select("role,is_active").eq("id", targetId).maybeSingle();
    if (targetError || !target) return json({ error: "No se encontró el usuario." }, 404);
    if (targetId === callerId && !isActive) return json({ error: "No puedes desactivar tu propia sesión administrativa." }, 400);
    if (target.role === "admin" && target.is_active && (role !== "admin" || !isActive)) {
      const { count, error } = await adminDb.from("profiles").select("id", { count: "exact", head: true }).eq("role", "admin").eq("is_active", true);
      if (error) return json({ error: "No se pudo comprobar el número de administradores activos." }, 500);
      if ((count ?? 0) <= 1) return json({ error: "No puedes desactivar o cambiar el rol del último administrador activo." }, 409);
    }
    const { error: authUpdateError } = await adminDb.auth.admin.updateUserById(targetId, {
      ban_duration: isActive ? "none" : "876000h",
    });
    if (authUpdateError) return json({ error: "No se pudo actualizar el acceso de la cuenta: " + authUpdateError.message }, 400);
    const { error } = await adminDb.from("profiles").update({
      full_name: fullName, phone, role, is_active: isActive, updated_at: new Date().toISOString(),
    }).eq("id", targetId);
    if (error) {
      await adminDb.auth.admin.updateUserById(targetId, { ban_duration: target.is_active ? "none" : "876000h" });
      return json({ error: error.message }, 400);
    }
    return json({ ok: true });
  }

  if (body.action === "delete") {
    if (targetId === callerId) return json({ error: "No puedes eliminar tu propia cuenta de administrador." }, 400);

    const { data: target, error: targetError } = await adminDb.from("profiles").select("role").eq("id", targetId).maybeSingle();
    if (targetError || !target) return json({ error: "No se encontró el usuario." }, 404);
    if (target.role === "admin") {
      const { count, error } = await adminDb.from("profiles").select("id", { count: "exact", head: true }).eq("role", "admin");
      if (error) return json({ error: "No se pudo comprobar el número de administradores." }, 500);
      if ((count ?? 0) <= 1) return json({ error: "No puedes eliminar al último administrador." }, 409);
    }

    // orders.user_id uses ON DELETE RESTRICT. Preserve purchase history and refuse
    // deletion where orders exist rather than destroying or orphaning commerce records.
    const { count: orderCount, error: orderError } = await adminDb.from("orders").select("id", { count: "exact", head: true }).eq("user_id", targetId);
    if (orderError) return json({ error: "No se pudo comprobar el historial de pedidos." }, 500);
    if ((orderCount ?? 0) > 0) return json({ error: "Este usuario tiene pedidos asociados. Para conservar el historial de compras, no se puede eliminar su cuenta desde aquí." }, 409);

    const { error: deleteError } = await adminDb.auth.admin.deleteUser(targetId);
    if (deleteError) return json({ error: deleteError.message }, 400);
    return json({ ok: true });
  }

  return json({ error: "Acción no reconocida." }, 400);
});
