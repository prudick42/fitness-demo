--
-- PostgreSQL database dump
--

\restrict Wh4OaBALUZ0mOXDgv9NumsEdk5T4gZ7Qy4WHnK8YqpPexVT2Ikn5S4sjRDebeXr

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.0

-- Started on 2025-12-25 02:33:00

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
-- TOC entry 891 (class 1247 OID 16586)
-- Name: booking_status_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.booking_status_enum AS ENUM (
    'записан',
    'отменил'
);


ALTER TYPE public.booking_status_enum OWNER TO postgres;

--
-- TOC entry 875 (class 1247 OID 16556)
-- Name: email_type; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public.email_type AS character varying(100)
	CONSTRAINT email_type_check CHECK (((VALUE)::text ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'::text));


ALTER DOMAIN public.email_type OWNER TO postgres;

--
-- TOC entry 879 (class 1247 OID 16559)
-- Name: gender_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.gender_enum AS ENUM (
    'М',
    'Ж'
);


ALTER TYPE public.gender_enum OWNER TO postgres;

--
-- TOC entry 871 (class 1247 OID 16553)
-- Name: name_type; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public.name_type AS character varying(100) NOT NULL;


ALTER DOMAIN public.name_type OWNER TO postgres;

--
-- TOC entry 885 (class 1247 OID 16572)
-- Name: payment_method_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.payment_method_enum AS ENUM (
    'наличные',
    'карта',
    'онлайн'
);


ALTER TYPE public.payment_method_enum OWNER TO postgres;

--
-- TOC entry 867 (class 1247 OID 16550)
-- Name: price_type; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public.price_type AS numeric(10,2)
	CONSTRAINT price_type_check CHECK ((VALUE >= (0)::numeric));


ALTER DOMAIN public.price_type OWNER TO postgres;

--
-- TOC entry 882 (class 1247 OID 16564)
-- Name: subscription_type_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.subscription_type_enum AS ENUM (
    'стандарт',
    'премиум',
    'безлимит'
);


ALTER TYPE public.subscription_type_enum OWNER TO postgres;

--
-- TOC entry 888 (class 1247 OID 16580)
-- Name: training_type_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.training_type_enum AS ENUM (
    'персональная',
    'групповая'
);


ALTER TYPE public.training_type_enum OWNER TO postgres;

--
-- TOC entry 232 (class 1255 OID 16704)
-- Name: calculate_subscription_end(date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_subscription_end(payment_date date, duration_days integer) RETURNS date
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN payment_date + duration_days;
END;
$$;


ALTER FUNCTION public.calculate_subscription_end(payment_date date, duration_days integer) OWNER TO postgres;

--
-- TOC entry 231 (class 1255 OID 16703)
-- Name: check_client_age(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_client_age() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.birth_date IS NOT NULL 
       AND NEW.birth_date > CURRENT_DATE - INTERVAL '16 years' THEN
        RAISE EXCEPTION 'Клиент должен быть старше 16 лет!';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_client_age() OWNER TO postgres;

--
-- TOC entry 245 (class 1255 OID 16724)
-- Name: check_visit_limit(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_visit_limit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sub_max_visits INT;
    used_visits INT;
    sub_id INT;
BEGIN
    -- Получаем ID абонемента из покупки
    SELECT id_subscription INTO sub_id
    FROM subscription_purchase 
    WHERE id_purchase = NEW.id_purchase;
    
    -- Получаем максимальное количество посещений для этого абонемента
    SELECT max_visits INTO sub_max_visits
    FROM subscriptions 
    WHERE id_subscription = sub_id;
    
    -- Если у абонемента есть ограничение по посещениям
    IF sub_max_visits IS NOT NULL AND sub_max_visits > 0 THEN
        -- Считаем количество уже использованных посещений (только активные записи)
        SELECT COUNT(*) INTO used_visits
        FROM bookings b
        JOIN subscription_purchase sp ON b.id_purchase = sp.id_purchase
        WHERE sp.id_subscription = sub_id
          AND b.booking_status = 'записан'
          AND sp.id_client = (
              SELECT id_client FROM subscription_purchase WHERE id_purchase = NEW.id_purchase
          );
        
        -- Проверяем, не превышен ли лимит
        IF used_visits >= sub_max_visits THEN
            RAISE EXCEPTION 'Превышен лимит посещений по абонементу! Максимум: % посещений', sub_max_visits;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_visit_limit() OWNER TO postgres;

--
-- TOC entry 233 (class 1255 OID 16706)
-- Name: prevent_double_booking(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prevent_double_booking() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    existing_count INT;
BEGIN
    SELECT COUNT(*)
    INTO existing_count
    FROM bookings b
    JOIN subscription_purchase sp ON b.id_purchase = sp.id_purchase
    WHERE sp.id_client = (
        SELECT id_client FROM subscription_purchase WHERE id_purchase = NEW.id_purchase
    )
    AND b.id_session = NEW.id_session;

    IF existing_count > 0 THEN
        RAISE EXCEPTION 'Клиент уже записан на это занятие!';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_double_booking() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 230 (class 1259 OID 16680)
-- Name: bookings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bookings (
    id_booking integer NOT NULL,
    id_purchase integer NOT NULL,
    id_session integer NOT NULL,
    booking_date date DEFAULT CURRENT_DATE NOT NULL,
    booking_status public.booking_status_enum DEFAULT 'записан'::public.booking_status_enum NOT NULL
);


ALTER TABLE public.bookings OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16679)
-- Name: bookings_id_booking_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bookings_id_booking_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bookings_id_booking_seq OWNER TO postgres;

--
-- TOC entry 5121 (class 0 OID 0)
-- Dependencies: 229
-- Name: bookings_id_booking_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bookings_id_booking_seq OWNED BY public.bookings.id_booking;


--
-- TOC entry 220 (class 1259 OID 16592)
-- Name: clients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clients (
    id_client integer NOT NULL,
    full_name public.name_type,
    phone character varying(20) NOT NULL,
    email public.email_type,
    birth_date date,
    gender public.gender_enum,
    CONSTRAINT clients_birth_date_check CHECK (((birth_date IS NULL) OR (birth_date <= (CURRENT_DATE - '16 years'::interval)))),
    CONSTRAINT clients_phone_check CHECK (((phone)::text ~ '^\+7[0-9]{10}$'::text))
);


ALTER TABLE public.clients OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16591)
-- Name: clients_id_client_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.clients_id_client_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clients_id_client_seq OWNER TO postgres;

--
-- TOC entry 5124 (class 0 OID 0)
-- Dependencies: 219
-- Name: clients_id_client_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.clients_id_client_seq OWNED BY public.clients.id_client;


--
-- TOC entry 226 (class 1259 OID 16638)
-- Name: subscription_purchase; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subscription_purchase (
    id_purchase integer NOT NULL,
    id_client integer NOT NULL,
    id_subscription integer NOT NULL,
    payment_amount public.price_type NOT NULL,
    payment_date date DEFAULT CURRENT_DATE NOT NULL,
    payment_method public.payment_method_enum
);


ALTER TABLE public.subscription_purchase OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16637)
-- Name: subscription_purchase_id_purchase_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subscription_purchase_id_purchase_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subscription_purchase_id_purchase_seq OWNER TO postgres;

--
-- TOC entry 5127 (class 0 OID 0)
-- Dependencies: 225
-- Name: subscription_purchase_id_purchase_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subscription_purchase_id_purchase_seq OWNED BY public.subscription_purchase.id_purchase;


--
-- TOC entry 224 (class 1259 OID 16621)
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subscriptions (
    id_subscription integer NOT NULL,
    subscription_type public.subscription_type_enum NOT NULL,
    price public.price_type NOT NULL,
    duration_days integer NOT NULL,
    max_visits integer,
    CONSTRAINT subscriptions_duration_days_check CHECK ((duration_days > 0)),
    CONSTRAINT subscriptions_max_visits_check CHECK ((max_visits >= 0))
);


ALTER TABLE public.subscriptions OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16620)
-- Name: subscriptions_id_subscription_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subscriptions_id_subscription_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subscriptions_id_subscription_seq OWNER TO postgres;

--
-- TOC entry 5130 (class 0 OID 0)
-- Dependencies: 223
-- Name: subscriptions_id_subscription_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subscriptions_id_subscription_seq OWNED BY public.subscriptions.id_subscription;


--
-- TOC entry 222 (class 1259 OID 16609)
-- Name: trainers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trainers (
    id_trainer integer NOT NULL,
    trainer_name public.name_type,
    specialization character varying(100) NOT NULL,
    experience integer,
    CONSTRAINT trainers_experience_check CHECK ((experience >= 0))
);


ALTER TABLE public.trainers OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16608)
-- Name: trainers_id_trainer_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.trainers_id_trainer_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.trainers_id_trainer_seq OWNER TO postgres;

--
-- TOC entry 5133 (class 0 OID 0)
-- Dependencies: 221
-- Name: trainers_id_trainer_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.trainers_id_trainer_seq OWNED BY public.trainers.id_trainer;


--
-- TOC entry 228 (class 1259 OID 16663)
-- Name: training_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.training_sessions (
    id_session integer NOT NULL,
    session_date date NOT NULL,
    session_time time without time zone NOT NULL,
    training_type public.training_type_enum NOT NULL,
    id_trainer integer NOT NULL
);


ALTER TABLE public.training_sessions OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16662)
-- Name: training_sessions_id_session_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.training_sessions_id_session_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.training_sessions_id_session_seq OWNER TO postgres;

--
-- TOC entry 5136 (class 0 OID 0)
-- Dependencies: 227
-- Name: training_sessions_id_session_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.training_sessions_id_session_seq OWNED BY public.training_sessions.id_session;


--
-- TOC entry 4918 (class 2604 OID 16683)
-- Name: bookings id_booking; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookings ALTER COLUMN id_booking SET DEFAULT nextval('public.bookings_id_booking_seq'::regclass);


--
-- TOC entry 4912 (class 2604 OID 16595)
-- Name: clients id_client; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clients ALTER COLUMN id_client SET DEFAULT nextval('public.clients_id_client_seq'::regclass);


--
-- TOC entry 4915 (class 2604 OID 16641)
-- Name: subscription_purchase id_purchase; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_purchase ALTER COLUMN id_purchase SET DEFAULT nextval('public.subscription_purchase_id_purchase_seq'::regclass);


--
-- TOC entry 4914 (class 2604 OID 16624)
-- Name: subscriptions id_subscription; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions ALTER COLUMN id_subscription SET DEFAULT nextval('public.subscriptions_id_subscription_seq'::regclass);


--
-- TOC entry 4913 (class 2604 OID 16612)
-- Name: trainers id_trainer; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trainers ALTER COLUMN id_trainer SET DEFAULT nextval('public.trainers_id_trainer_seq'::regclass);


--
-- TOC entry 4917 (class 2604 OID 16666)
-- Name: training_sessions id_session; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.training_sessions ALTER COLUMN id_session SET DEFAULT nextval('public.training_sessions_id_session_seq'::regclass);


--
-- TOC entry 5110 (class 0 OID 16680)
-- Dependencies: 230
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bookings (id_booking, id_purchase, id_session, booking_date, booking_status) FROM stdin;
1	5	13	2025-12-20	отменил
2	5	17	2025-12-25	записан
3	5	18	2025-12-25	записан
4	5	20	2025-12-25	записан
5	5	19	2025-12-25	записан
6	5	21	2025-12-25	записан
7	5	23	2025-12-25	записан
8	5	22	2025-12-25	записан
9	5	24	2025-12-25	записан
11	5	26	2025-12-25	записан
12	5	25	2025-12-25	записан
13	5	28	2025-12-25	записан
14	5	29	2025-12-25	отменил
10	5	27	2025-12-25	отменил
\.


--
-- TOC entry 5100 (class 0 OID 16592)
-- Dependencies: 220
-- Data for Name: clients; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clients (id_client, full_name, phone, email, birth_date, gender) FROM stdin;
3	Руди Кирилл Олегович	+79080442071	okrud05@mail.ru	2005-06-05	М
8	Данилов Матвей Сергеевич	+79080442072	kirichrudi@gmail.com	2005-04-17	М
15	Смирнов Дмитрий Алексеевич	+79991112233	smirnov@mail.ru	1990-05-15	М
16	Кузнецова Анна Викторовна	+79992223344	kuznetsova@gmail.com	1995-08-22	Ж
17	Васильев Павел Сергеевич	+79993334455	vasiliev@yandex.ru	1988-12-10	М
18	Руди Дарья Олеговна	+79080567872	dshmk67@mail.ru	2008-12-12	Ж
\.


--
-- TOC entry 5106 (class 0 OID 16638)
-- Dependencies: 226
-- Data for Name: subscription_purchase; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subscription_purchase (id_purchase, id_client, id_subscription, payment_amount, payment_date, payment_method) FROM stdin;
4	18	10	3000.00	2025-12-20	наличные
5	3	10	3000.00	2025-12-20	карта
\.


--
-- TOC entry 5104 (class 0 OID 16621)
-- Dependencies: 224
-- Data for Name: subscriptions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subscriptions (id_subscription, subscription_type, price, duration_days, max_visits) FROM stdin;
10	стандарт	3000.00	30	12
11	премиум	5000.00	30	24
12	безлимит	8000.00	30	\N
\.


--
-- TOC entry 5102 (class 0 OID 16609)
-- Dependencies: 222
-- Data for Name: trainers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trainers (id_trainer, trainer_name, specialization, experience) FROM stdin;
7	Иванов Иван Иванович	Силовые тренировки	5
8	Петрова Мария Сергеевна	Йога и пилатес	8
9	Сидоров Алексей Петрович	Кардио тренировки	3
\.


--
-- TOC entry 5108 (class 0 OID 16663)
-- Dependencies: 228
-- Data for Name: training_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.training_sessions (id_session, session_date, session_time, training_type, id_trainer) FROM stdin;
13	2025-12-21	10:00:00	групповая	7
14	2025-12-21	12:00:00	персональная	8
15	2025-12-22	15:00:00	групповая	9
16	2025-12-22	18:00:00	персональная	7
17	2025-12-26	10:50:00	персональная	8
18	2025-12-26	12:00:00	персональная	7
19	2025-12-27	18:20:00	групповая	8
20	2025-12-27	06:30:00	персональная	9
21	2025-12-29	10:30:00	групповая	9
22	2025-12-31	12:30:00	групповая	8
23	2025-12-30	11:30:00	персональная	9
24	2026-01-01	20:00:00	персональная	7
25	2026-01-02	10:30:00	групповая	8
26	2026-01-04	20:00:00	групповая	9
27	2026-01-07	18:30:00	персональная	7
28	2025-12-30	08:30:00	персональная	9
29	2026-01-08	20:00:00	групповая	8
\.


--
-- TOC entry 5138 (class 0 OID 0)
-- Dependencies: 229
-- Name: bookings_id_booking_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bookings_id_booking_seq', 16, true);


--
-- TOC entry 5139 (class 0 OID 0)
-- Dependencies: 219
-- Name: clients_id_client_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clients_id_client_seq', 18, true);


--
-- TOC entry 5140 (class 0 OID 0)
-- Dependencies: 225
-- Name: subscription_purchase_id_purchase_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subscription_purchase_id_purchase_seq', 5, true);


--
-- TOC entry 5141 (class 0 OID 0)
-- Dependencies: 223
-- Name: subscriptions_id_subscription_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subscriptions_id_subscription_seq', 12, true);


--
-- TOC entry 5142 (class 0 OID 0)
-- Dependencies: 221
-- Name: trainers_id_trainer_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trainers_id_trainer_seq', 9, true);


--
-- TOC entry 5143 (class 0 OID 0)
-- Dependencies: 227
-- Name: training_sessions_id_session_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.training_sessions_id_session_seq', 29, true);


--
-- TOC entry 4943 (class 2606 OID 16692)
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id_booking);


--
-- TOC entry 4927 (class 2606 OID 16607)
-- Name: clients clients_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_email_key UNIQUE (email);


--
-- TOC entry 4929 (class 2606 OID 16605)
-- Name: clients clients_phone_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_phone_key UNIQUE (phone);


--
-- TOC entry 4931 (class 2606 OID 16603)
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id_client);


--
-- TOC entry 4939 (class 2606 OID 16651)
-- Name: subscription_purchase subscription_purchase_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_purchase
    ADD CONSTRAINT subscription_purchase_pkey PRIMARY KEY (id_purchase);


--
-- TOC entry 4935 (class 2606 OID 16634)
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id_subscription);


--
-- TOC entry 4937 (class 2606 OID 16636)
-- Name: subscriptions subscriptions_subscription_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_subscription_type_key UNIQUE (subscription_type);


--
-- TOC entry 4933 (class 2606 OID 16619)
-- Name: trainers trainers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trainers
    ADD CONSTRAINT trainers_pkey PRIMARY KEY (id_trainer);


--
-- TOC entry 4941 (class 2606 OID 16673)
-- Name: training_sessions training_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.training_sessions
    ADD CONSTRAINT training_sessions_pkey PRIMARY KEY (id_session);


--
-- TOC entry 4949 (class 2620 OID 16705)
-- Name: clients trg_check_client_age; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_check_client_age BEFORE INSERT OR UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.check_client_age();


--
-- TOC entry 4950 (class 2620 OID 16725)
-- Name: bookings trg_check_visit_limit; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_check_visit_limit BEFORE INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.check_visit_limit();


--
-- TOC entry 4951 (class 2620 OID 16707)
-- Name: bookings trg_prevent_double_booking; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_prevent_double_booking BEFORE INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.prevent_double_booking();


--
-- TOC entry 4947 (class 2606 OID 16693)
-- Name: bookings bookings_id_purchase_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_id_purchase_fkey FOREIGN KEY (id_purchase) REFERENCES public.subscription_purchase(id_purchase) ON DELETE CASCADE;


--
-- TOC entry 4948 (class 2606 OID 16698)
-- Name: bookings bookings_id_session_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_id_session_fkey FOREIGN KEY (id_session) REFERENCES public.training_sessions(id_session) ON DELETE CASCADE;


--
-- TOC entry 4944 (class 2606 OID 16652)
-- Name: subscription_purchase subscription_purchase_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_purchase
    ADD CONSTRAINT subscription_purchase_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.clients(id_client) ON DELETE CASCADE;


--
-- TOC entry 4945 (class 2606 OID 16657)
-- Name: subscription_purchase subscription_purchase_id_subscription_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subscription_purchase
    ADD CONSTRAINT subscription_purchase_id_subscription_fkey FOREIGN KEY (id_subscription) REFERENCES public.subscriptions(id_subscription) ON DELETE CASCADE;


--
-- TOC entry 4946 (class 2606 OID 16674)
-- Name: training_sessions training_sessions_id_trainer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.training_sessions
    ADD CONSTRAINT training_sessions_id_trainer_fkey FOREIGN KEY (id_trainer) REFERENCES public.trainers(id_trainer) ON DELETE CASCADE;


--
-- TOC entry 5116 (class 0 OID 0)
-- Dependencies: 5
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO admin_role;
GRANT USAGE ON SCHEMA public TO client_role;
GRANT USAGE ON SCHEMA public TO trainer_role;
GRANT USAGE ON SCHEMA public TO manager_role;


--
-- TOC entry 5117 (class 0 OID 0)
-- Dependencies: 232
-- Name: FUNCTION calculate_subscription_end(payment_date date, duration_days integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_subscription_end(payment_date date, duration_days integer) TO admin_role;
GRANT ALL ON FUNCTION public.calculate_subscription_end(payment_date date, duration_days integer) TO client_role;
GRANT ALL ON FUNCTION public.calculate_subscription_end(payment_date date, duration_days integer) TO trainer_role;
GRANT ALL ON FUNCTION public.calculate_subscription_end(payment_date date, duration_days integer) TO manager_role;


--
-- TOC entry 5118 (class 0 OID 0)
-- Dependencies: 231
-- Name: FUNCTION check_client_age(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.check_client_age() TO admin_role;
GRANT ALL ON FUNCTION public.check_client_age() TO client_role;
GRANT ALL ON FUNCTION public.check_client_age() TO trainer_role;
GRANT ALL ON FUNCTION public.check_client_age() TO manager_role;


--
-- TOC entry 5119 (class 0 OID 0)
-- Dependencies: 233
-- Name: FUNCTION prevent_double_booking(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.prevent_double_booking() TO admin_role;
GRANT ALL ON FUNCTION public.prevent_double_booking() TO client_role;
GRANT ALL ON FUNCTION public.prevent_double_booking() TO trainer_role;
GRANT ALL ON FUNCTION public.prevent_double_booking() TO manager_role;


--
-- TOC entry 5120 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE bookings; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.bookings TO client_role;
GRANT SELECT ON TABLE public.bookings TO trainer_role;
GRANT SELECT ON TABLE public.bookings TO manager_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.bookings TO admin_role;


--
-- TOC entry 5122 (class 0 OID 0)
-- Dependencies: 229
-- Name: SEQUENCE bookings_id_booking_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.bookings_id_booking_seq TO admin_role;
GRANT SELECT,USAGE ON SEQUENCE public.bookings_id_booking_seq TO client_role;
GRANT SELECT,USAGE ON SEQUENCE public.bookings_id_booking_seq TO trainer_role;
GRANT SELECT,USAGE ON SEQUENCE public.bookings_id_booking_seq TO manager_role;


--
-- TOC entry 5123 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE clients; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.clients TO client_role;
GRANT SELECT ON TABLE public.clients TO trainer_role;
GRANT SELECT ON TABLE public.clients TO manager_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.clients TO admin_role;


--
-- TOC entry 5125 (class 0 OID 0)
-- Dependencies: 219
-- Name: SEQUENCE clients_id_client_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.clients_id_client_seq TO admin_role;
GRANT SELECT,USAGE ON SEQUENCE public.clients_id_client_seq TO client_role;
GRANT SELECT,USAGE ON SEQUENCE public.clients_id_client_seq TO trainer_role;
GRANT SELECT,USAGE ON SEQUENCE public.clients_id_client_seq TO manager_role;


--
-- TOC entry 5126 (class 0 OID 0)
-- Dependencies: 226
-- Name: TABLE subscription_purchase; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.subscription_purchase TO client_role;
GRANT SELECT ON TABLE public.subscription_purchase TO manager_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.subscription_purchase TO admin_role;


--
-- TOC entry 5128 (class 0 OID 0)
-- Dependencies: 225
-- Name: SEQUENCE subscription_purchase_id_purchase_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.subscription_purchase_id_purchase_seq TO admin_role;
GRANT SELECT,USAGE ON SEQUENCE public.subscription_purchase_id_purchase_seq TO client_role;
GRANT SELECT,USAGE ON SEQUENCE public.subscription_purchase_id_purchase_seq TO trainer_role;
GRANT SELECT,USAGE ON SEQUENCE public.subscription_purchase_id_purchase_seq TO manager_role;


--
-- TOC entry 5129 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE subscriptions; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.subscriptions TO client_role;
GRANT SELECT ON TABLE public.subscriptions TO manager_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.subscriptions TO admin_role;
GRANT SELECT ON TABLE public.subscriptions TO trainer_role;


--
-- TOC entry 5131 (class 0 OID 0)
-- Dependencies: 223
-- Name: SEQUENCE subscriptions_id_subscription_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.subscriptions_id_subscription_seq TO admin_role;
GRANT SELECT,USAGE ON SEQUENCE public.subscriptions_id_subscription_seq TO client_role;
GRANT SELECT,USAGE ON SEQUENCE public.subscriptions_id_subscription_seq TO trainer_role;
GRANT SELECT,USAGE ON SEQUENCE public.subscriptions_id_subscription_seq TO manager_role;


--
-- TOC entry 5132 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE trainers; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.trainers TO client_role;
GRANT SELECT ON TABLE public.trainers TO trainer_role;
GRANT SELECT ON TABLE public.trainers TO manager_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.trainers TO admin_role;


--
-- TOC entry 5134 (class 0 OID 0)
-- Dependencies: 221
-- Name: SEQUENCE trainers_id_trainer_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.trainers_id_trainer_seq TO admin_role;
GRANT SELECT,USAGE ON SEQUENCE public.trainers_id_trainer_seq TO client_role;
GRANT SELECT,USAGE ON SEQUENCE public.trainers_id_trainer_seq TO trainer_role;
GRANT SELECT,USAGE ON SEQUENCE public.trainers_id_trainer_seq TO manager_role;


--
-- TOC entry 5135 (class 0 OID 0)
-- Dependencies: 228
-- Name: TABLE training_sessions; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.training_sessions TO client_role;
GRANT SELECT ON TABLE public.training_sessions TO trainer_role;
GRANT SELECT ON TABLE public.training_sessions TO manager_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.training_sessions TO admin_role;


--
-- TOC entry 5137 (class 0 OID 0)
-- Dependencies: 227
-- Name: SEQUENCE training_sessions_id_session_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.training_sessions_id_session_seq TO admin_role;
GRANT SELECT,USAGE ON SEQUENCE public.training_sessions_id_session_seq TO client_role;
GRANT SELECT,USAGE ON SEQUENCE public.training_sessions_id_session_seq TO trainer_role;
GRANT SELECT,USAGE ON SEQUENCE public.training_sessions_id_session_seq TO manager_role;


-- Completed on 2025-12-25 02:33:00

--
-- PostgreSQL database dump complete
--

\unrestrict Wh4OaBALUZ0mOXDgv9NumsEdk5T4gZ7Qy4WHnK8YqpPexVT2Ikn5S4sjRDebeXr

