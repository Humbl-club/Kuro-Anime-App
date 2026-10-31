// Destination storage for mirror-images. The bucket and object path are not taken
// from the request: only the `media` bucket and a catalog-derived path are writable.

export const ALLOWED_BUCKET = "media";

const SAFE_OBJECT_PATH =
  /^(anime|manga|characters|staff)\/\d+(?:\/(?:cover_large|cover_medium|banner))?\.(?:jpg|png|webp|avif)$/;

export type MirrorStorage = {
  upload(
    bucket: string,
    path: string,
    bytes: Uint8Array,
    opts: { contentType: string; cacheControl: string; upsert: boolean },
  ): Promise<{ error: { message: string } | null }>;
  publicUrl(bucket: string, path: string): string;
};

// deno-lint-ignore no-explicit-any
export function createMirrorStorage(supabase: any): MirrorStorage {
  return {
    async upload(bucket, path, bytes, opts) {
      if (bucket !== ALLOWED_BUCKET) return { error: { message: "invalid_bucket" } };
      if (!SAFE_OBJECT_PATH.test(path)) return { error: { message: "invalid_path" } };
      const { error } = await supabase.storage.from(bucket).upload(path, new Blob([bytes], { type: opts.contentType }), {
        upsert: opts.upsert,
        contentType: opts.contentType,
        cacheControl: opts.cacheControl,
      });
      return { error: error ?? null };
    },
    publicUrl(bucket, path) {
      const { data } = supabase.storage.from(bucket).getPublicUrl(path);
      return data.publicUrl;
    },
  };
}
