const express = require('express');
const router = express.Router();
const db = require('../config/database');

const clean = (arr) => arr.map(v => v === undefined ? null : v);

router.post('/login-customer', async (req, res) => {
    try {
        const { phone } = req.body;
        const [rows] = await db.execute('SELECT * FROM customer WHERE PhoneNumber = ?', clean([phone]));
        if (rows.length > 0) res.json({ success: true, user: rows[0] });
        else res.json({ success: false, message: "Không tìm thấy SĐT này!" });
    } catch (error) { res.status(500).json({ success: false, message: error.message }); }
});

router.get('/my-orders/:customerId', async (req, res) => {
    try {
        const keyword = req.query.search ? `%${req.query.search}%` : '%';
        const [rows] = await db.execute(
            `SELECT TrackingNumber, OrderName, ShippingFee, CreatedDate 
             FROM shipment WHERE (Sender_ID = ? OR Receiver_ID = ?) AND OrderName LIKE ? 
             ORDER BY CreatedDate DESC`,
            clean([req.params.customerId, req.params.customerId, keyword])
        );
        res.json({ success: true, data: rows });
    } catch (error) { res.status(500).json({ success: false }); }
});

router.post('/create-order', async (req, res) => {
    const conn = await db.getConnection(); 
    try {
        await conn.beginTransaction();
        const { orderName, codAmount, receiverName, receiverPhone, province, detailAddress, senderId, items } = req.body;

        const [locs] = await conn.execute('SELECT LocationID FROM locations WHERE Province = ?', clean([province]));
        if (locs.length === 0) throw new Error("Tỉnh/Thành này nằm ngoài phạm vi giao hàng!");
        const locationId = locs[0].LocationID || locs[0].locationid || locs[0].locationId;

        let receiverId;
        const [recvs] = await conn.execute('SELECT CustomerID FROM customer WHERE PhoneNumber = ?', clean([receiverPhone]));
        if (recvs.length > 0) {
            receiverId = recvs[0].CustomerID || recvs[0].customerid || recvs[0].customerId;
        } else {
            const [newC] = await conn.execute('INSERT INTO customer (FullName, PhoneNumber) VALUES (?, ?)', clean([receiverName, receiverPhone]));
            receiverId = newC.insertId;
        }

        const trackingNumber = 'VN' + Math.floor(100000 + Math.random() * 900000);

        await conn.execute(
            `INSERT INTO SHIPMENT (TrackingNumber, OrderName, CODAmount, ShippingFee, Detail_Address, LocationID, Sender_ID, Receiver_ID) 
             VALUES (?, ?, ?, 0, ?, ?, ?, ?)`,
            clean([trackingNumber, orderName, codAmount, detailAddress, locationId, senderId, receiverId])
        );

        for (let item of items || []) {
            await conn.execute(
                `INSERT INTO ITEMS (NameItem, TrackingNumber, amounts, Weight, Dimensions, Type) VALUES (?, ?, ?, ?, ?, ?)`,
                clean([item.name, trackingNumber, item.amount, item.weight, item.dimensions, item.type])
            );
        }

        await conn.execute(`INSERT INTO TRACKING_LOG (StatusDescription, TrackingNumber) VALUES ('Chờ xử lý', ?)`, clean([trackingNumber]));

        await conn.commit(); 
        res.json({ success: true, trackingNumber: trackingNumber });
    } catch (error) {
        await conn.rollback(); 
        res.status(400).json({ success: false, message: error.message });
    } finally {
        conn.release(); 
    }
});

router.get('/track/:trackingNumber', async (req, res) => {
    try {
        const [orderInfo] = await db.execute('SELECT * FROM vw_fullorderdetails WHERE TrackingNumber = ?', clean([req.params.trackingNumber]));
        const [logs] = await db.execute('SELECT UpdateTimestamp, StatusDescription FROM tracking_log WHERE TrackingNumber = ? ORDER BY UpdateTimestamp DESC', clean([req.params.trackingNumber]));
        const [items] = await db.execute('SELECT NameItem, Weight, amounts FROM items WHERE TrackingNumber = ?', clean([req.params.trackingNumber]));

        if (orderInfo.length > 0) res.json({ success: true, order: orderInfo[0], logs: logs, items: items });
        else res.json({ success: false, message: "Không tìm thấy đơn hàng." });
    } catch (error) { res.status(500).json({ success: false }); }
});

module.exports = router;