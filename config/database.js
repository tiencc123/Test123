const mysql = require('mysql2/promise');

const dbPool = mysql.createPool({
    host: 'localhost',
    user: 'root',
    password: 'tien1515', // <--- Thay mật khẩu của bạn
    database: 'logistics',
    waitForConnections: true,
    connectionLimit: 15, // Hỗ trợ nhiều người truy cập cùng lúc
    queueLimit: 0
});

console.log("✅ Hệ thống đã kết nối Trạm dữ liệu MySQL (Connection Pool)");
module.exports = dbPool;