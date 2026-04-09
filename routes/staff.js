const express = require('express');
const router = express.Router();
const db = require('../config/database');

const clean = (arr) => arr.map(v => v === undefined ? null : v);

// 1. Đăng nhập Staff
router.post('/login', async (req, res) => {
    try {
        const { id, name } = req.body;
        const [rows] = await db.execute(
            `SELECT p.EmployeeID, p.FullName, p.HubID, h.HubName 
             FROM personnel p 
             JOIN staff s ON p.EmployeeID = s.EmployeeID 
             LEFT JOIN hub h ON p.HubID = h.HubID
             WHERE p.EmployeeID = ? AND p.FullName = ?`, clean([id, name])
        );
        if (rows.length > 0) res.json({ success: true, user: rows[0] });
        else res.json({ success: false, message: "Sai ID hoặc Tên! Chắc chắn người này nằm trong bảng STAFF." });
    } catch (error) { res.status(500).json({ success: false, message: error.message }); }
});

// 2. Tồn kho (Lấy TẤT CẢ hàng đang nằm tại kho này)
router.get('/inventory/:hubId', async (req, res) => {
    try {
        // Đã bỏ điều kiện lọc RoutingType để hiện toàn bộ hàng hóa
        const [rows] = await db.execute(
            "SELECT * FROM vw_hubinventory WHERE CurrentHubID = ?", 
            [req.params.hubId]
        );
        res.json({ success: true, data: rows });
    } catch (error) { res.status(500).json({ success: false }); }
});

// 3. Lấy xe tải (Trucker) đang Rảnh VÀ THUỘC KHO HIỆN TẠI
router.get('/available-truckers/:hubId', async (req, res) => {
    try {
        const [rows] = await db.execute(
            `SELECT p.EmployeeID, p.FullName, v.LicensePlate, vt.MaxPayload 
             FROM personnel p 
             JOIN trucker t ON p.EmployeeID = t.EmployeeID 
             JOIN driver d ON p.EmployeeID = d.EmployeeID 
             JOIN vehicle v ON t.LicensePlate = v.LicensePlate 
             JOIN vehicle_type vt ON v.TypeID = vt.TypeID 
             WHERE d.Status = 'Sẵn sàng' AND p.HubID = ?`, clean([req.params.hubId])
        );
        res.json({ success: true, data: rows });
    } catch (error) { res.status(500).json({ success: false }); }
});

// 4. Chất hàng lên xe
router.post('/load', async (req, res) => {
    try {
        await db.execute('CALL sp_LoadToTruck(?, ?)', clean([req.body.trackingNumber, req.body.truckerId]));
        res.json({ success: true, message: "Đã xếp lên xe!" });
    } catch (error) { res.status(400).json({ success: false, message: error.message }); }
});

// 5. Chốt chuyến (Xe tải xuất phát)
router.post('/dispatch', async (req, res) => {
    try {
        await db.execute('CALL sp_DispatchTruck(?)', clean([req.body.truckerId]));
        res.json({ success: true, message: "Xe tải đã xuất phát!" });
    } catch (error) { res.status(400).json({ success: false, message: error.message }); }
});

// 6. Tìm xe tải ĐANG chở hàng đến kho này
router.get('/incoming-trucks/:hubId', async (req, res) => {
    try {
        const [rows] = await db.execute(
            `SELECT DISTINCT p.EmployeeID, p.FullName, v.LicensePlate 
             FROM shipment s JOIN locations l ON s.LocationID = l.LocationID
             JOIN trucker t ON s.Driver_ID = t.EmployeeID JOIN personnel p ON t.EmployeeID = p.EmployeeID
             JOIN vehicle v ON t.LicensePlate = v.LicensePlate
             WHERE l.HubID = ? AND s.HubID IS NULL`, clean([req.params.hubId])
        );
        res.json({ success: true, data: rows });
    } catch (error) { res.status(500).json({ success: false }); }
});

// 7. Nhập kho từ xe tải đến
router.post('/receive-truck', async (req, res) => {
    try {
        const { truckerId, staffId, hubId } = req.body;
        const [orders] = await db.execute(
            `SELECT s.TrackingNumber FROM shipment s JOIN locations l ON s.LocationID = l.LocationID
             WHERE s.Driver_ID = ? AND l.HubID = ? AND s.HubID IS NULL`, clean([truckerId, hubId])
        );
        for (let order of orders) {
            await db.execute('CALL sp_ReceiveFromTrucker(?, ?)', clean([order.TrackingNumber, staffId]));
        }
        const [leftovers] = await db.execute('SELECT TrackingNumber FROM shipment WHERE Driver_ID = ?', clean([truckerId]));
        if (leftovers.length === 0) {
            await db.execute('CALL sp_CompleteTruckRoute(?)', clean([truckerId]));
        }
        res.json({ success: true, message: `Đã nhập kho ${orders.length} đơn hàng!` });
    } catch (error) { res.status(400).json({ success: false, message: error.message }); }
});

module.exports = router;