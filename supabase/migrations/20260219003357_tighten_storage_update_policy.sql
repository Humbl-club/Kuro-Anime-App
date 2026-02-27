-- Fix storage UPDATE policy: add owner_id check to WITH CHECK
-- Was missing owner_id validation in WITH CHECK clause
DROP POLICY IF EXISTS "Authenticated users can update own media" ON storage.objects;
CREATE POLICY "Authenticated users can update own media" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'media' AND (auth.uid())::text = owner_id)
  WITH CHECK (bucket_id = 'media' AND (auth.uid())::text = owner_id);;
