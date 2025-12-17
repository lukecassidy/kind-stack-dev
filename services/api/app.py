#!/usr/bin/env python3
import os
from flask import Flask, jsonify, request
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

# Database configuration from environment variables
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'postgres'),
    'port': os.getenv('DB_PORT', '5432'),
    'database': os.getenv('DB_NAME', 'appdb'),
    'user': os.getenv('DB_USER', 'appuser'),
    'password': os.getenv('DB_PASSWORD', 'devpassword')
}

def get_db_connection():
    """Create a database connection."""
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

@app.route('/health')
def health():
    """Health check endpoint."""
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({'status': 'healthy', 'database': 'connected'}), 200
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503

@app.route('/')
def root():
    """Root endpoint with API information."""
    return jsonify({
        'service': 'API Service',
        'version': '1.0.0',
        'endpoints': {
            'health': '/health',
            'users': {
                'list': 'GET /users',
                'get': 'GET /users/<id>',
                'create': 'POST /users'
            },
            'posts': {
                'list': 'GET /posts',
                'get': 'GET /posts/<id>',
                'create': 'POST /posts',
                'by_user': 'GET /users/<id>/posts'
            }
        }
    }), 200

# Users endpoints
@app.route('/users', methods=['GET'])
def list_users():
    """List all users."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT id, username, email, created_at FROM users ORDER BY id')
        users = cur.fetchall()
        cur.close()
        conn.close()
        return jsonify(users), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get a specific user."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT id, username, email, created_at FROM users WHERE id = %s', (user_id,))
        user = cur.fetchone()
        cur.close()
        conn.close()

        if user:
            return jsonify(user), 200
        else:
            return jsonify({'error': 'User not found'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/users', methods=['POST'])
def create_user():
    """Create a new user."""
    try:
        data = request.get_json()

        if not data or 'username' not in data or 'email' not in data:
            return jsonify({'error': 'username and email are required'}), 400

        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            'INSERT INTO users (username, email) VALUES (%s, %s) RETURNING id, username, email, created_at',
            (data['username'], data['email'])
        )
        user = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        return jsonify(user), 201
    except psycopg2.IntegrityError as e:
        return jsonify({'error': 'Username or email already exists'}), 409
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Posts endpoints
@app.route('/posts', methods=['GET'])
def list_posts():
    """List all posts."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('''
            SELECT p.id, p.title, p.content, p.status, p.created_at,
                   p.user_id, u.username
            FROM posts p
            LEFT JOIN users u ON p.user_id = u.id
            ORDER BY p.created_at DESC
        ''')
        posts = cur.fetchall()
        cur.close()
        conn.close()
        return jsonify(posts), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/posts/<int:post_id>', methods=['GET'])
def get_post(post_id):
    """Get a specific post."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('''
            SELECT p.id, p.title, p.content, p.status, p.created_at,
                   p.user_id, u.username
            FROM posts p
            LEFT JOIN users u ON p.user_id = u.id
            WHERE p.id = %s
        ''', (post_id,))
        post = cur.fetchone()
        cur.close()
        conn.close()

        if post:
            return jsonify(post), 200
        else:
            return jsonify({'error': 'Post not found'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/posts', methods=['POST'])
def create_post():
    """Create a new post."""
    try:
        data = request.get_json()

        if not data or 'user_id' not in data or 'title' not in data:
            return jsonify({'error': 'user_id and title are required'}), 400

        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('''
            INSERT INTO posts (user_id, title, content, status)
            VALUES (%s, %s, %s, %s)
            RETURNING id, user_id, title, content, status, created_at
        ''', (
            data['user_id'],
            data['title'],
            data.get('content', ''),
            data.get('status', 'draft')
        ))
        post = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        return jsonify(post), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/users/<int:user_id>/posts', methods=['GET'])
def get_user_posts(user_id):
    """Get all posts by a specific user."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('''
            SELECT p.id, p.title, p.content, p.status, p.created_at,
                   p.user_id, u.username
            FROM posts p
            LEFT JOIN users u ON p.user_id = u.id
            WHERE p.user_id = %s
            ORDER BY p.created_at DESC
        ''', (user_id,))
        posts = cur.fetchall()
        cur.close()
        conn.close()
        return jsonify(posts), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
