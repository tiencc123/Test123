const express = require('express');
const router = express.Router();
const db = require('../config/database');

const clean = (arr) => arr.map(v => v === undefined ? null : v);

router.post('/login', async (req, res) => {
    try {
        const { id, name } = req.body;
        // Đã sửa thành LEFT JOIN để đăng nhập được ngay cả khi chưa phân kho
        const [rows] = await db.execute(
            `SELECT p.EmployeeID, p.FullName, p.HubID, h.HubName 
             FROM personnel p 
             JOIN driver d ON p.EmployeeID = d.EmployeeID
             JOIN courier c ON d.EmployeeID = c.EmployeeID 
             LEFT JOIN hub h ON p.HubID = h.HubID
             WHERE p.EmployeeID = ? AND p.FullName = ?`, clean([id, name])
        );
        if (rows.length > 0) res.json({ success: true, user: rows[0] });
        else res.json({ success: false, message: "Sai ID hoặc Tên tài xế! Hãy kiểm tra bảng COURIER." });
    } catch (error) { res.status(500).json({ success: false, message: error.message }); }
});

router.get('/tasks/:hubId', async (req, res) => {
    try {
        const [rows] = await db.execute('SELECT * FROM vw_couriertasks WHERE HubID = ?', clean([req.params.hubId]));
        res.json({ success: true, data: rows });
    } catch (error) { res.status(500).json({ success: false }); }
});

router.get('/my-bag/:driverId', async (req, res) => {
    try {
        const driverId = req.params.driverId || '';
        // SỬA Ở ĐÂY: Truy vấn thêm dòng trạng thái mới nhất từ tracking_log
        const [rows] = await db.execute(`
            SELECT s.TrackingNumber, s.Detail_Address, s.HubID, s.CODAmount, s.OrderName,
                   (SELECT StatusDescription FROM tracking_log WHERE TrackingNumber = s.TrackingNumber ORDER BY LogID DESC LIMIT 1) AS LastLog
            FROM shipment s 
            WHERE s.Driver_ID = ?`, [driverId]);
        res.json({ success: true, data: rows });
    } catch (error) { res.status(500).json({ success: false }); }
});

// 4. Nhận đơn hàng (Đã phân tách Lấy hàng và Giao hàng)
router.post('/accept', async (req, res) => {
    try {
        const tn = req.body.trackingNumber || '';
        const did = req.body.driverId || '';
        const actionType = req.body.actionType || 'pickup';
        
        // Gọi thủ tục khác nhau tùy vào loại nhiệm vụ
        if (actionType === 'pickup') {
            await db.execute('CALL sp_DriverAcceptOrder(?, ?)', [tn, did]);
        } else {
            await db.execute('CALL sp_DriverDeliveryOutbound(?, ?)', [tn, did]);
        }
        res.json({ success: true, message: "Đã nhận đơn!" });
    } catch (error) { res.status(400).json({ success: false, message: error.message }); }
});

router.post('/complete', async (req, res) => {
    try {
        const { trackingNumber, driverId, actionType } = req.body;
        if (actionType === 'inbound') {
            await db.execute('CALL sp_ConfirmInboundHub(?, ?)', clean([trackingNumber, driverId]));
        } else {
            await db.execute('CALL sp_DeliverySuccess(?, ?)', clean([trackingNumber, driverId]));
        }
        res.json({ success: true, message: "Xử lý thành công!" });
    } catch (error) { res.status(400).json({ success: false, message: error.message }); }
});

module.exports = router;