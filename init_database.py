import psycopg2
from psycopg2 import Error
from datetime import datetime, timedelta

DB_CONFIG = {
    'host': 'localhost',
    'port': '5433',
    'database': 'gym_db',
    'user': 'postgres',
    'password': '1685'
}

def init_database():
    """Инициализация базы данных с тестовыми данными"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        print("🔄 Очистка существующих данных...")
        
        cursor.execute("DELETE FROM bookings;")
        cursor.execute("DELETE FROM training_sessions;")
        cursor.execute("DELETE FROM subscription_purchase;")
        cursor.execute("DELETE FROM clients;")
        cursor.execute("DELETE FROM trainers;")
        cursor.execute("DELETE FROM subscriptions;")
        
        print("✅ Данные очищены")
        
        print("👨‍🏫 Добавляем тренеров...")
        cursor.execute("""
            INSERT INTO trainers (trainer_name, specialization, experience) VALUES
            ('Иванов Иван Иванович', 'Силовые тренировки', 5),
            ('Петрова Мария Сергеевна', 'Йога и пилатес', 8),
            ('Сидоров Алексей Петрович', 'Кардио тренировки', 3)
            RETURNING id_trainer;
        """)
        
        trainer_ids = cursor.fetchall()
        print(f"✅ Добавлены тренеры с id: {[id[0] for id in trainer_ids]}")
        
        print("🎫 Добавляем типы абонементов...")
        cursor.execute("""
            INSERT INTO subscriptions (subscription_type, price, duration_days, max_visits) VALUES
            ('стандарт', 3000.00, 30, 12),
            ('премиум', 5000.00, 30, 24),
            ('безлимит', 8000.00, 30, NULL)
            RETURNING id_subscription;
        """)
        
        subscription_ids = cursor.fetchall()
        print(f"✅ Добавлены абонементы с id: {[id[0] for id in subscription_ids]}")
        
        print("👥 Добавляем клиентов...")
        cursor.execute("""
            INSERT INTO clients (full_name, phone, email, birth_date, gender) VALUES
            ('Смирнов Дмитрий Алексеевич', '+79991112233', 'smirnov@mail.ru', '1990-05-15', 'М'),
            ('Кузнецова Анна Викторовна', '+79992223344', 'kuznetsova@gmail.com', '1995-08-22', 'Ж'),
            ('Васильев Павел Сергеевич', '+79993334455', 'vasiliev@yandex.ru', '1988-12-10', 'М')
            RETURNING id_client;
        """)
        
        client_ids = cursor.fetchall()
        print(f"✅ Добавлены клиенты с id: {[id[0] for id in client_ids]}")
        
        print("🏋️ Добавляем тренировки...")
        today = datetime.now().date()
        cursor.execute("""
            INSERT INTO training_sessions (session_date, session_time, training_type, id_trainer) VALUES
            (%s, '10:00:00', 'групповая', 1),
            (%s, '12:00:00', 'персональная', 2),
            (%s, '15:00:00', 'групповая', 3),
            (%s, '18:00:00', 'персональная', 1)
            RETURNING id_session;
        """, (today + timedelta(days=1), today + timedelta(days=1), 
              today + timedelta(days=2), today + timedelta(days=2)))
        
        training_ids = cursor.fetchall()
        print(f"✅ Добавлены тренировки с id: {[id[0] for id in training_ids]}")
        
        print("💰 Добавляем покупки абонементов...")
        cursor.execute("""
            INSERT INTO subscription_purchase (id_client, id_subscription, payment_amount, payment_date, payment_method) VALUES
            (1, 1, 3000.00, CURRENT_DATE - INTERVAL '5 days', 'карта'),
            (2, 2, 5000.00, CURRENT_DATE - INTERVAL '3 days', 'онлайн'),
            (3, 3, 8000.00, CURRENT_DATE, 'наличные')
            RETURNING id_purchase;
        """)
        
        purchase_ids = cursor.fetchall()
        print(f"✅ Добавлены покупки с id: {[id[0] for id in purchase_ids]}")
        
        conn.commit()
        print("🎉 База данных успешно инициализирована!")
        
        print("\n📊 Статистика базы данных:")
        cursor.execute("SELECT COUNT(*) FROM trainers;")
        print(f"Тренеров: {cursor.fetchone()[0]}")
        
        cursor.execute("SELECT COUNT(*) FROM clients;")
        print(f"Клиентов: {cursor.fetchone()[0]}")
        
        cursor.execute("SELECT COUNT(*) FROM training_sessions;")
        print(f"Тренировок: {cursor.fetchone()[0]}")
        
        cursor.execute("SELECT COUNT(*) FROM subscription_purchase;")
        print(f"Покупок абонементов: {cursor.fetchone()[0]}")
        
        cursor.close()
        conn.close()
        
    except Error as e:
        print(f"❌ Ошибка при инициализации БД: {e}")
        if conn:
            conn.rollback()

if __name__ == '__main__':
    print("=" * 50)
    print("Инициализация базы данных фитнес-клуба")
    print("=" * 50)
    
    response = input("Это удалит все существующие данные. Продолжить? (y/N): ")
    if response.lower() == 'y':
        init_database()
    else:
        print("Отменено.")