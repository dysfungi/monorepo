SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: touch_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.touch_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: concerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.concerts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id text DEFAULT 'default'::text NOT NULL,
    songkick_uid text NOT NULL,
    artist text NOT NULL,
    venue text NOT NULL,
    city text NOT NULL,
    country text NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    tz text NOT NULL,
    plan_status text DEFAULT 'going'::text NOT NULL,
    calendar_uid text,
    content_hash text,
    calendar_sequence integer DEFAULT 0 NOT NULL,
    calendar_sent_at timestamp with time zone,
    calendar_attempts integer DEFAULT 0 NOT NULL,
    calendar_last_error text,
    probable_setlist jsonb,
    probable_setlist_computed_at timestamp with time zone,
    setlist_notified_at timestamp with time zone,
    setlist_found_at timestamp with time zone,
    setlist_attempts integer DEFAULT 0 NOT NULL,
    setlist_last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    calendar_first_failed_at timestamp with time zone,
    calendar_alerted_at timestamp with time zone,
    setlist_first_failed_at timestamp with time zone,
    setlist_alerted_at timestamp with time zone,
    songkick_event_url text,
    event_start_at timestamp with time zone,
    doors_at timestamp with time zone,
    show_at timestamp with time zone,
    openers text,
    ticket_vendor text,
    ticket_url text,
    enriched_at timestamp with time zone
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying(128) NOT NULL
);


--
-- Name: concerts concerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.concerts
    ADD CONSTRAINT concerts_pkey PRIMARY KEY (id);


--
-- Name: concerts concerts_songkick_uid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.concerts
    ADD CONSTRAINT concerts_songkick_uid_key UNIQUE (songkick_uid);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: concerts touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON public.concerts FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at_column();


--
-- PostgreSQL database dump complete
--


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('20260630000001'),
    ('20260630000002'),
    ('20260701000001'),
    ('20260701000002');
