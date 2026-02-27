-- Add missing FK indexes for query performance
CREATE INDEX IF NOT EXISTS idx_club_messages_user_id ON public.club_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_rag_retrieval_feedback_selected_entity_id ON public.rag_retrieval_feedback(selected_entity_id);;
