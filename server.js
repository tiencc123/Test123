const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Kết nối các bộ phận logic
app.use('/api/customer', require('./routes/customer'));
app.use('/api/courier', require('./routes/courier'));
app.use('/api/staff', require('./routes/staff'));

app.listen(3000, () => {
    console.log("-----------------------------------------");
    console.log("🚀 HỆ THỐNG LOGISTICS ĐANG HOẠT ĐỘNG");
    console.log("🔗 Khách hàng: http://localhost:3000/customer.html");
    console.log("🔗 Tài xế: http://localhost:3000/courier.html");
    console.log("🔗 Thủ kho: http://localhost:3000/staff.html");
    console.log("-----------------------------------------");
});