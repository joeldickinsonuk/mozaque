import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Use POST to delete your account.' }, 405)

  const authorization = req.headers.get('Authorization')
  if (!authorization?.startsWith('Bearer ')) return json({ error: 'Please sign in again.' }, 401)

  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !anonKey || !serviceRoleKey) {
    console.error('Account deletion is missing a required Supabase secret.')
    return json({ error: 'Account deletion is temporarily unavailable. Please try again later.' }, 503)
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const admin = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  try {
    const token = authorization.slice('Bearer '.length)
    const { data: { user }, error: authError } = await caller.auth.getUser(token)
    if (authError || !user) return json({ error: 'Your session has expired. Please sign in again.' }, 401)

    // Storage objects must be removed through the Storage API before Auth can
    // delete their owner. Include images in galleries owned by this person,
    // images they uploaded to shared galleries, and their profile image.
    const [ownedGalleries, uploadedPhotos, profile] = await Promise.all([
      admin.from('galleries').select('id').eq('owner_id', user.id),
      admin.from('photos').select('storage_path').eq('uploader_id', user.id),
      admin.from('profiles').select('avatar_path').eq('id', user.id).maybeSingle(),
    ])
    for (const result of [ownedGalleries, uploadedPhotos, profile]) {
      if (result.error) throw result.error
    }

    const galleryIds = (ownedGalleries.data ?? []).map((row) => row.id as string)
    let ownedGalleryPhotos: { storage_path: string }[] = []
    if (galleryIds.length > 0) {
      const result = await admin.from('photos').select('storage_path').in('gallery_id', galleryIds)
      if (result.error) throw result.error
      ownedGalleryPhotos = result.data ?? []
    }

    const photoPaths = new Set<string>()
    for (const row of uploadedPhotos.data ?? []) photoPaths.add(row.storage_path as string)
    for (const row of ownedGalleryPhotos) photoPaths.add(row.storage_path)
    const allPhotoPaths = [...photoPaths]
    for (let start = 0; start < allPhotoPaths.length; start += 1000) {
      const { error } = await admin.storage.from('mozaque-photos').remove(allPhotoPaths.slice(start, start + 1000))
      if (error) throw error
    }

    const avatarPath = profile.data?.avatar_path
    if (typeof avatarPath === 'string' && avatarPath.length > 0) {
      const { error } = await admin.storage.from('profile-photos').remove([avatarPath])
      if (error) throw error
    }

    // The database profile references auth.users with ON DELETE CASCADE, which
    // removes galleries, photos, social records, notifications and messages.
    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id)
    if (deleteError) throw deleteError
    return json({ success: true })
  } catch (error) {
    console.error('Account deletion failed:', error)
    return json({ error: 'We could not finish deleting your account. Your account has not been removed; please try again.' }, 500)
  }
})
