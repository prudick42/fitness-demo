from flask import Flask, render_template, request, redirect, url_for, flash, session
import psycopg2
from psycopg2 import Error
from functools import wraps

app = Flask(__name__)
app.secret_key = 'dev-secret-key-123'

# Маппинг ролей пользователей PostgreSQL
USER_ROLES = {
    'admin_user': 'admin',
    'client_user': 'client', 
    'trainer_user': 'trainer',
    'manager_user': 'manager'
}

# Базовые настройки подключения (для проверки пользователей)
BASE_DB_CONFIG = {
    'host': 'localhost',
    'port': '5433',
    'database': 'gym_db'
}

def authenticate_postgres_user(username, password):
    """Аутентификация через подключение к PostgreSQL под указанным пользователем"""
    try:
        # Пробуем подключиться как указанный пользователь
        config = BASE_DB_CONFIG.copy()
        config['user'] = username
        config['password'] = password
        
        conn = psycopg2.connect(**config)
        
        # Если подключение успешно - пользователь существует и пароль верный
        conn.close()
        
        # Возвращаем роль пользователя
        return USER_ROLES.get(username)
        
    except Error:
        return None

def get_db_connection():
    """Создание подключения к БД для работы приложения"""
    try:
        # Используем admin_user для всех операций в приложении
        # (так как у него есть права на все таблицы)
        config = BASE_DB_CONFIG.copy()
        config['user'] = 'admin_user'
        config['password'] = '123'
        
        conn = psycopg2.connect(**config)
        return conn
    except Error as e:
        print(f"❌ Ошибка подключения к БД: {e}")
        return None

# Декоратор для проверки роли
def role_required(required_role):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if 'username' not in session:
                flash('Сначала войдите в систему')
                return redirect(url_for('login'))
            if session['role'] not in required_role:
                flash('У вас нет доступа к этой странице')
                return redirect(url_for('dashboard'))
            return f(*args, **kwargs)
        return decorated_function
    return decorator

@app.route('/')
def index():
    """Главная страница"""
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Вход в систему с использованием PostgreSQL пользователей"""
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if not username or not password:
            flash('Введите логин и пароль')
            return render_template('login.html')
        
        # Пробуем аутентифицировать пользователя
        role = authenticate_postgres_user(username, password)
        
        if role:
            # Сохраняем данные в сессии
            session['username'] = username
            session['role'] = role
            
            # Получаем дополнительную информацию о пользователе
            conn = get_db_connection()
            if conn:
                cur = conn.cursor()
                
                try:
                    if role == 'client':
                        # Для клиента получаем информацию о первом клиенте
                        cur.execute("SELECT id_client, full_name FROM clients LIMIT 1")
                        client_data = cur.fetchone()
                        if client_data:
                            session['user_id'] = client_data[0]
                            session['display_name'] = client_data[1]
                        else:
                            session['display_name'] = username
                            
                    elif role == 'trainer':
                        # Для тренера получаем информацию о первом тренере
                        cur.execute("SELECT id_trainer, trainer_name FROM trainers LIMIT 1")
                        trainer_data = cur.fetchone()
                        if trainer_data:
                            session['user_id'] = trainer_data[0]
                            session['display_name'] = trainer_data[1]
                        else:
                            session['display_name'] = username
                            
                    else:
                        # Для admin и manager
                        session['display_name'] = username
                        
                except Error as e:
                    print(f"Ошибка при получении данных пользователя: {e}")
                    session['display_name'] = username
                    
                finally:
                    cur.close()
                    conn.close()
            
            flash(f'Добро пожаловать, {session["display_name"]}!')
            return redirect(url_for('dashboard'))
        else:
            flash('Неверный логин или пароль')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    """Выход из системы"""
    session.clear()
    flash('Вы вышли из системы')
    return redirect(url_for('login'))

@app.route('/dashboard')
def dashboard():
    """Панель управления в зависимости от роли"""
    if 'username' not in session:
        return redirect(url_for('login'))
    
    role = session['role']
    
    # Получаем данные для dashboard в зависимости от роли
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return render_template('dashboard.html', role=role, data={})
    
    cur = conn.cursor()
    data = {}
    
    try:
        if role == 'admin':
            # Статистика для администратора
            cur.execute("SELECT COUNT(*) FROM clients")
            data['clients_count'] = cur.fetchone()[0]
            
            cur.execute("SELECT COUNT(*) FROM trainers")
            data['trainers_count'] = cur.fetchone()[0]
            
            cur.execute("SELECT COUNT(*) FROM training_sessions")
            data['trainings_count'] = cur.fetchone()[0]
            
            # Последние 5 клиентов
            cur.execute("SELECT * FROM clients ORDER BY id_client DESC LIMIT 5")
            data['recent_clients'] = cur.fetchall()
            
        elif role == 'client':
            # Для клиента используем первый ID клиента (для демо)
            client_id = session.get('user_id', 1)
            
            cur.execute("""
                SELECT id_client, full_name, phone, email, 
                       birth_date, gender 
                FROM clients 
                WHERE id_client = %s
            """, (client_id,))
            
            client_data = cur.fetchone()
            
            if client_data:
                data['client'] = {
                    'id': client_data[0],
                    'name': client_data[1],
                    'phone': client_data[2],
                    'email': client_data[3],
                    'birth_date': client_data[4],
                    'gender': client_data[5]
                }
                
                # Получаем активный абонемент
                cur.execute("""
                    SELECT s.subscription_type, s.price, 
                           sp.payment_date, sp.payment_method,
                           s.duration_days
                    FROM subscription_purchase sp
                    JOIN subscriptions s ON sp.id_subscription = s.id_subscription
                    WHERE sp.id_client = %s
                    ORDER BY sp.payment_date DESC
                    LIMIT 1
                """, (client_id,))
                
                subscription = cur.fetchone()
                if subscription:
                    data['subscription'] = {
                        'type': subscription[0],
                        'price': subscription[1],
                        'date': subscription[2],
                        'method': subscription[3],
                        'duration': subscription[4]
                    }
        
        elif role == 'trainer':
            # Для тренера используем первый ID тренера (для демо)
            trainer_id = session.get('user_id', 1)
            
            cur.execute("""
                SELECT id_trainer, trainer_name, specialization, experience
                FROM trainers 
                WHERE id_trainer = %s
            """, (trainer_id,))
            
            trainer_data = cur.fetchone()
            if trainer_data:
                data['trainer'] = {
                    'id': trainer_data[0],
                    'name': trainer_data[1],
                    'specialization': trainer_data[2],
                    'experience': trainer_data[3]
                }
            
            # Ближайшие тренировки тренера
            cur.execute("""
                SELECT ts.session_date, ts.session_time, ts.training_type
                FROM training_sessions ts
                WHERE ts.id_trainer = %s AND ts.session_date >= CURRENT_DATE
                ORDER BY ts.session_date, ts.session_time
                LIMIT 5
            """, (trainer_id,))
            
            data['upcoming_trainings'] = cur.fetchall()
            
        elif role == 'manager':
            # Финансовая статистика
            cur.execute("SELECT SUM(payment_amount) FROM subscription_purchase")
            total_revenue = cur.fetchone()[0]
            data['total_revenue'] = total_revenue or 0
            
            cur.execute("SELECT COUNT(*) FROM subscription_purchase")
            data['total_sales'] = cur.fetchone()[0]
            
            # Статистика по абонементам
            cur.execute("""
                SELECT s.subscription_type, COUNT(*), SUM(sp.payment_amount)
                FROM subscription_purchase sp
                JOIN subscriptions s ON sp.id_subscription = s.id_subscription
                GROUP BY s.subscription_type
            """)
            data['subscription_stats'] = cur.fetchall()
    
    except Error as e:
        print(f"Ошибка при получении данных: {e}")
        flash(f'Ошибка при получении данных: {e}')
    
    finally:
        cur.close()
        conn.close()
    
    return render_template('dashboard.html', role=role, data=data)

# ВСЕ ОСТАЛЬНЫЕ МАРШРУТЫ (clients, trainers, subscriptions, bookings и т.д.)
# ОСТАЮТСЯ БЕЗ ИЗМЕНЕНИЙ, КАК В ПРЕДЫДУЩЕЙ ВЕРСИИ
# Просто скопируйте их из вашего текущего app.py

# Маршруты для управления клиентами
@app.route('/clients')
@role_required(['admin', 'manager'])
def clients():
    """Показать всех клиентов (доступ: admin, manager)"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    cur.execute('SELECT * FROM clients ORDER BY id_client')
    clients_data = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return render_template('clients.html', clients=clients_data)

@app.route('/add_client', methods=['GET', 'POST'])
@role_required(['admin'])
def add_client():
    """Добавить нового клиента (доступ: только admin)"""
    if request.method == 'POST':
        full_name = request.form['full_name']
        phone = request.form['phone']
        email = request.form['email'] or None
        birth_date = request.form['birth_date'] if request.form['birth_date'] else None
        gender = request.form['gender']
        
        conn = get_db_connection()
        if not conn:
            flash('Ошибка подключения к базе данных')
            return redirect(url_for('dashboard'))
        
        try:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO clients (full_name, phone, email, birth_date, gender)
                VALUES (%s, %s, %s, %s, %s)
            """, (full_name, phone, email, birth_date, gender))
            
            conn.commit()
            flash('Клиент успешно добавлен!')
            
        except Error as e:
            flash(f'Ошибка при добавлении клиента: {e}')
            conn.rollback()
        finally:
            cur.close()
            conn.close()
        
        return redirect(url_for('clients'))
    
    return render_template('add_client.html')

# Маршруты для тренеров
@app.route('/trainers')
@role_required(['admin', 'manager'])
def trainers_list():
    """Список всех тренеров"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    cur.execute('SELECT * FROM trainers ORDER BY id_trainer')
    trainers = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return render_template('trainers.html', trainers=trainers)

@app.route('/add_trainer', methods=['GET', 'POST'])
@role_required(['admin'])
def add_trainer():
    """Добавить нового тренера"""
    if request.method == 'POST':
        trainer_name = request.form['trainer_name']
        specialization = request.form['specialization']
        experience = request.form['experience']
        
        conn = get_db_connection()
        if not conn:
            flash('Ошибка подключения к базе данных')
            return redirect(url_for('dashboard'))
        
        try:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO trainers (trainer_name, specialization, experience)
                VALUES (%s, %s, %s)
            """, (trainer_name, specialization, experience))
            
            conn.commit()
            flash('Тренер успешно добавлен!')
            
        except Error as e:
            flash(f'Ошибка при добавлении тренера: {e}')
            conn.rollback()
        finally:
            cur.close()
            conn.close()
        
        return redirect(url_for('trainers_list'))
    
    return render_template('add_trainer.html')

# Маршруты для абонементов
@app.route('/subscriptions')
@role_required(['admin', 'client', 'manager', 'trainer'])
def subscriptions():
    """Показать все типы абонементов (доступ: все роли)"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    cur.execute('SELECT * FROM subscriptions ORDER BY id_subscription')
    subscriptions_data = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return render_template('subscriptions.html', subscriptions=subscriptions_data)

@app.route('/buy_subscription', methods=['GET', 'POST'])
@role_required(['admin', 'client'])
def buy_subscription():
    """Купить абонемент (доступ: admin, client)"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    
    # Для клиента показываем только его
    if session['role'] == 'client':
        cur.execute("SELECT id_client, full_name FROM clients ORDER BY id_client LIMIT 1")
    else:
        # Для админа показываем всех клиентов
        cur.execute('SELECT id_client, full_name FROM clients ORDER BY full_name')
    
    clients_data = cur.fetchall()
    
    cur.execute('SELECT id_subscription, subscription_type, price FROM subscriptions ORDER BY id_subscription')
    subscriptions_data = cur.fetchall()
    
    if request.method == 'POST':
        client_id = request.form['client_id']
        subscription_id = request.form['subscription_id']
        payment_method = request.form['payment_method']
        
        try:
            # Получаем цену абонемента
            cur.execute('SELECT price FROM subscriptions WHERE id_subscription = %s', (subscription_id,))
            price_result = cur.fetchone()
            if price_result:
                price = price_result[0]
            else:
                flash('Абонемент не найден')
                return redirect(url_for('buy_subscription'))
            
            # Добавляем покупку
            cur.execute("""
                INSERT INTO subscription_purchase 
                (id_client, id_subscription, payment_amount, payment_method)
                VALUES (%s, %s, %s, %s)
            """, (client_id, subscription_id, price, payment_method))
            
            conn.commit()
            flash('Абонемент успешно куплен!')
            
        except Error as e:
            flash(f'Ошибка при покупке абонемента: {e}')
            conn.rollback()
        finally:
            cur.close()
            conn.close()
        
        return redirect(url_for('subscriptions'))
    
    cur.close()
    conn.close()
    
    return render_template('buy_subscription.html', 
                          clients=clients_data, 
                          subscriptions=subscriptions_data)

# Маршруты для тренировок
@app.route('/trainings')
@role_required(['admin', 'client', 'trainer', 'manager'])
def trainings():
    """Показать все тренировки (доступ: все роли)"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    cur.execute("""
        SELECT ts.id_session, ts.session_date, ts.session_time, 
               ts.training_type, t.trainer_name, t.id_trainer
        FROM training_sessions ts
        JOIN trainers t ON ts.id_trainer = t.id_trainer
        ORDER BY ts.session_date, ts.session_time
    """)
    trainings_data = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return render_template('trainings.html', trainings=trainings_data)

@app.route('/add_training', methods=['GET', 'POST'])
@role_required(['admin'])
def add_training():
    """Добавить тренировку (доступ: только admin)"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    
    try:
        # Получаем список тренеров для выбора
        cur.execute('SELECT id_trainer, trainer_name FROM trainers ORDER BY trainer_name')
        trainers = cur.fetchall()
        
        # Проверяем, есть ли тренеры
        if not trainers:
            flash('Нет тренеров. Сначала добавьте тренеров!')
            return redirect(url_for('dashboard'))
        
        if request.method == 'POST':
            session_date = request.form['session_date']
            session_time = request.form['session_time']
            training_type = request.form['training_type']
            id_trainer = request.form['id_trainer']
            
            # Проверяем, что тренер существует
            cur.execute("SELECT id_trainer FROM trainers WHERE id_trainer = %s", (id_trainer,))
            if not cur.fetchone():
                flash('Выбранный тренер не существует!')
                return redirect(url_for('add_training'))
            
            cur.execute("""
                INSERT INTO training_sessions 
                (session_date, session_time, training_type, id_trainer)
                VALUES (%s, %s, %s, %s)
            """, (session_date, session_time, training_type, id_trainer))
            
            conn.commit()
            flash('Тренировка успешно добавлена!')
            
            return redirect(url_for('trainings'))
        
    except Error as e:
        flash(f'Ошибка при добавлении тренировки: {e}')
        conn.rollback()
    
    finally:
        cur.close()
        conn.close()
    
    return render_template('add_training.html', trainers=trainers)

# Маршруты для записей на тренировки
@app.route('/bookings')
@role_required(['admin', 'client', 'trainer'])
def bookings_list():
    """Показать все записи на тренировки"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    
    # В зависимости от роли показываем разные записи
    if session['role'] == 'client':
        # Для клиента показываем только его записи (первого клиента)
        cur.execute("SELECT id_client FROM clients LIMIT 1")
        client_id_result = cur.fetchone()
        if client_id_result:
            client_id = client_id_result[0]
        else:
            flash('Клиенты не найдены в базе данных')
            return render_template('bookings.html', bookings=[])
        
        cur.execute("""
            SELECT 
                b.id_booking,
                c.full_name as client_name,
                ts.session_date,
                ts.session_time,
                ts.training_type,
                t.trainer_name,
                b.booking_date,
                b.booking_status
            FROM bookings b
            JOIN subscription_purchase sp ON b.id_purchase = sp.id_purchase
            JOIN clients c ON sp.id_client = c.id_client
            JOIN training_sessions ts ON b.id_session = ts.id_session
            JOIN trainers t ON ts.id_trainer = t.id_trainer
            WHERE sp.id_client = %s
            ORDER BY ts.session_date DESC, ts.session_time DESC
        """, (client_id,))
        
    elif session['role'] == 'trainer':
        # Для тренера показываем записи на его тренировки (первого тренера)
        cur.execute("SELECT id_trainer FROM trainers LIMIT 1")
        trainer_id_result = cur.fetchone()
        if trainer_id_result:
            trainer_id = trainer_id_result[0]
        else:
            flash('Тренеры не найдены в базе данных')
            return render_template('bookings.html', bookings=[])
        
        cur.execute("""
            SELECT 
                b.id_booking,
                c.full_name as client_name,
                ts.session_date,
                ts.session_time,
                ts.training_type,
                t.trainer_name,
                b.booking_date,
                b.booking_status
            FROM bookings b
            JOIN subscription_purchase sp ON b.id_purchase = sp.id_purchase
            JOIN clients c ON sp.id_client = c.id_client
            JOIN training_sessions ts ON b.id_session = ts.id_session
            JOIN trainers t ON ts.id_trainer = t.id_trainer
            WHERE ts.id_trainer = %s
            ORDER BY ts.session_date, ts.session_time
        """, (trainer_id,))
    
    else:
        # Для администратора показываем все записи
        cur.execute("""
            SELECT 
                b.id_booking,
                c.full_name as client_name,
                ts.session_date,
                ts.session_time,
                ts.training_type,
                t.trainer_name,
                b.booking_date,
                b.booking_status
            FROM bookings b
            JOIN subscription_purchase sp ON b.id_purchase = sp.id_purchase
            JOIN clients c ON sp.id_client = c.id_client
            JOIN training_sessions ts ON b.id_session = ts.id_session
            JOIN trainers t ON ts.id_trainer = t.id_trainer
            ORDER BY ts.session_date DESC, ts.session_time DESC
        """)
    
    bookings_data = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return render_template('bookings.html', bookings=bookings_data)

@app.route('/book_training', methods=['GET', 'POST'])
@role_required(['admin', 'client'])
def book_training():
    """Запись на тренировку (доступ: admin, client)"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    
    # Получаем список тренировок (только будущие)
    cur.execute("""
        SELECT ts.id_session, ts.session_date, ts.session_time, 
               ts.training_type, t.trainer_name
        FROM training_sessions ts
        JOIN trainers t ON ts.id_trainer = t.id_trainer
        WHERE ts.session_date >= CURRENT_DATE
        ORDER BY ts.session_date, ts.session_time
    """)
    trainings = cur.fetchall()
    
    # Получаем список клиентов (для администратора) и их активные покупки
    if session['role'] == 'admin':
        cur.execute('SELECT id_client, full_name FROM clients ORDER BY full_name')
        clients = cur.fetchall()
    else:
        # Для клиента показываем только его
        cur.execute("SELECT id_client, full_name FROM clients LIMIT 1")
        clients = cur.fetchall()
    
    if request.method == 'POST':
        client_id = request.form['client_id']
        session_id = request.form['session_id']
        
        # Проверяем, есть ли у клиента активная покупка абонемента
        cur.execute("""
            SELECT id_purchase 
            FROM subscription_purchase 
            WHERE id_client = %s 
            ORDER BY payment_date DESC 
            LIMIT 1
        """, (client_id,))
        
        purchase_result = cur.fetchone()
        
        if not purchase_result:
            flash('У клиента нет активного абонемента! Сначала купите абонемент.')
            return redirect(url_for('book_training'))
        
        id_purchase = purchase_result[0]
        
        try:
            # Проверяем, не записан ли уже клиент на эту тренировку
            cur.execute("""
                SELECT COUNT(*) 
                FROM bookings b
                JOIN subscription_purchase sp ON b.id_purchase = sp.id_purchase
                WHERE sp.id_client = %s AND b.id_session = %s
            """, (client_id, session_id))
            
            already_booked = cur.fetchone()[0]
            
            if already_booked > 0:
                flash('Клиент уже записан на эту тренировку!')
                return redirect(url_for('book_training'))
            
            # Создаем запись
            cur.execute("""
                INSERT INTO bookings (id_purchase, id_session, booking_status)
                VALUES (%s, %s, 'записан')
            """, (id_purchase, session_id))
            
            conn.commit()
            flash('Запись на тренировку успешно создана!')
            
        except Error as e:
            flash(f'Ошибка при записи на тренировку: {e}')
            conn.rollback()
        finally:
            cur.close()
            conn.close()
        
        return redirect(url_for('bookings_list'))
    
    cur.close()
    conn.close()
    
    return render_template('book_training.html', 
                          trainings=trainings, 
                          clients=clients)

@app.route('/cancel_booking/<int:booking_id>')
@role_required(['admin', 'client'])
def cancel_booking(booking_id):
    """Отмена записи на тренировку"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    
    try:
        # Проверяем, может ли текущий пользователь отменить эту запись
        if session['role'] == 'client':
            # Для клиента проверяем, что это его запись
            cur.execute("SELECT id_client FROM clients LIMIT 1")
            client_id_result = cur.fetchone()
            if client_id_result:
                client_id = client_id_result[0]
            else:
                flash('Клиент не найден')
                return redirect(url_for('bookings_list'))
            
            cur.execute("""
                SELECT b.id_booking
                FROM bookings b
                JOIN subscription_purchase sp ON b.id_purchase = sp.id_purchase
                WHERE b.id_booking = %s AND sp.id_client = %s
            """, (booking_id, client_id))
            
            if not cur.fetchone():
                flash('Вы не можете отменить эту запись')
                return redirect(url_for('bookings_list'))
        
        # Отменяем запись
        cur.execute("""
            UPDATE bookings 
            SET booking_status = 'отменил' 
            WHERE id_booking = %s
        """, (booking_id,))
        
        conn.commit()
        flash('Запись успешно отменена!')
        
    except Error as e:
        flash(f'Ошибка при отмене записи: {e}')
        conn.rollback()
    finally:
        cur.close()
        conn.close()
    
    return redirect(url_for('bookings_list'))

# Маршруты для отчетов
@app.route('/reports/financial')
@role_required(['manager', 'admin'])
def financial_report():
    """Финансовый отчет"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    
    # Общая выручка
    cur.execute("SELECT SUM(payment_amount) FROM subscription_purchase")
    total_revenue = cur.fetchone()[0] or 0
    
    # Выручка по месяцам
    cur.execute("""
        SELECT 
            EXTRACT(YEAR FROM payment_date) as year,
            EXTRACT(MONTH FROM payment_date) as month,
            COUNT(*) as sales_count,
            SUM(payment_amount) as month_revenue
        FROM subscription_purchase
        GROUP BY EXTRACT(YEAR FROM payment_date), EXTRACT(MONTH FROM payment_date)
        ORDER BY year DESC, month DESC
        LIMIT 6
    """)
    monthly_data = cur.fetchall()
    
    # Распределение по типам абонементов
    cur.execute("""
        SELECT 
            s.subscription_type,
            COUNT(*) as count,
            SUM(sp.payment_amount) as revenue,
            AVG(sp.payment_amount) as avg_price
        FROM subscription_purchase sp
        JOIN subscriptions s ON sp.id_subscription = s.id_subscription
        GROUP BY s.subscription_type
        ORDER BY revenue DESC
    """)
    subscription_stats = cur.fetchall()
    
    cur.close()
    conn.close()
    
    # Форматируем месяцы
    months = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 
              'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь']
    formatted_monthly_data = []
    for year, month, count, revenue in monthly_data:
        month_name = months[int(month)-1]
        formatted_monthly_data.append((f"{month_name} {int(year)}", count, revenue))
    
    return render_template('financial_report.html',
                         total_revenue=total_revenue,
                         monthly_data=formatted_monthly_data,
                         subscription_stats=subscription_stats)

@app.route('/reports/attendance')
@role_required(['manager', 'admin'])
def attendance_report():
    """Отчет по посещаемости"""
    conn = get_db_connection()
    if not conn:
        flash('Ошибка подключения к базе данных')
        return redirect(url_for('dashboard'))
    
    cur = conn.cursor()
    
    # Популярные тренировки
    cur.execute("""
        SELECT 
            training_type,
            COUNT(*) as session_count
        FROM training_sessions
        GROUP BY training_type
        ORDER BY session_count DESC
    """)
    training_stats = cur.fetchall()
    
    # Активные клиенты
    cur.execute("""
        SELECT 
            c.full_name,
            COUNT(sp.id_purchase) as subscriptions_count,
            SUM(sp.payment_amount) as total_spent
        FROM clients c
        LEFT JOIN subscription_purchase sp ON c.id_client = sp.id_client
        GROUP BY c.id_client, c.full_name
        HAVING COUNT(sp.id_purchase) > 0
        ORDER BY total_spent DESC NULLS LAST
        LIMIT 10
    """)
    active_clients = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return render_template('attendance_report.html',
                         training_stats=training_stats,
                         active_clients=active_clients)

@app.route('/switch_role')
def switch_role():
    """Переключение между ролями (демо)"""
    session.clear()
    flash('Выберите роль для входа')
    return redirect(url_for('login'))

if __name__ == '__main__':
    # Проверяем подключение к БД при запуске
    print("=" * 50)
    print("Запуск приложения фитнес-клуба")
    print("=" * 50)
    
    # Тестируем подключение как admin_user
    try:
        config = BASE_DB_CONFIG.copy()
        config['user'] = 'admin_user'
        config['password'] = '123'
        
        conn = psycopg2.connect(**config)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM trainers")
        trainer_count = cur.fetchone()[0]
        print(f"✅ Подключение к БД как admin_user установлено")
        print(f"📊 Тренеров в базе: {trainer_count}")
        
        # Проверяем доступные пользователи
        print("\n👤 Доступные пользователи для входа:")
        print("-" * 40)
        for pg_user, role in USER_ROLES.items():
            print(f"  Логин: {pg_user:<15} → Роль: {role}")
        print("-" * 40)
        print("  Пароль для всех пользователей: 123")
        
        cur.close()
        conn.close()
    except Error as e:
        print(f"❌ Не удалось подключиться к БД: {e}")
        print("Убедитесь, что:")
        print("1. PostgreSQL запущен")
        print("2. База данных 'gym_db' существует")
        print("3. Пользователи созданы (admin_user, client_user, trainer_user, manager_user)")
        print("4. Пароль у всех пользователей: 123")
    
    print("=" * 50)
    app.run(debug=True, port=5000)