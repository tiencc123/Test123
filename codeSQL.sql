CREATE TABLE courier (
  EmployeeID int NOT NULL,
  LicensePlate varchar(20),
  PRIMARY KEY (EmployeeID),
  FOREIGN KEY (EmployeeID) REFERENCES driver (EmployeeID)
);

CREATE TABLE customer (
  CustomerID int NOT NULL AUTO_INCREMENT,
  FullName varchar(100) NOT NULL,
  Email varchar(100),
  PhoneNumber varchar(15) NOT NULL,
  CustomerType varchar(50),
  Detail_Address varchar(255),
  LocationID int,
  PRIMARY KEY (CustomerID),
  UNIQUE KEY (PhoneNumber),
  UNIQUE KEY (Email),
  FOREIGN KEY (LocationID) REFERENCES locations (LocationID)
);

CREATE TABLE driver (
  EmployeeID int NOT NULL,
  Status varchar(50),
  LicenseNumber varchar(50),
  PRIMARY KEY (EmployeeID),
  UNIQUE KEY (LicenseNumber),
  FOREIGN KEY (EmployeeID) REFERENCES personnel (EmployeeID)
);

CREATE TABLE hub (
  HubID int NOT NULL AUTO_INCREMENT,
  HubName varchar(100) NOT NULL,
  Address varchar(255),
  Capacity decimal(12,2),
  ContactNumber varchar(15),
  PRIMARY KEY (HubID)
);

CREATE TABLE items (
  NameItem varchar(255) NOT NULL,
  TrackingNumber varchar(50) NOT NULL,
  amounts int DEFAULT '1',
  Weight decimal(10,2),
  Dimensions varchar(100),
  Type varchar(50),
  Fee decimal(15,2),
  PRIMARY KEY (NameItem, TrackingNumber),
  FOREIGN KEY (TrackingNumber) REFERENCES shipment (TrackingNumber) ON DELETE CASCADE
);

CREATE TABLE locations (
  LocationID int NOT NULL AUTO_INCREMENT,
  Province varchar(100) NOT NULL,
  HubID int,
  PRIMARY KEY (LocationID),
  FOREIGN KEY (HubID) REFERENCES hub (HubID)
);

CREATE TABLE personnel (
  EmployeeID int NOT NULL AUTO_INCREMENT,
  FullName varchar(100) NOT NULL,
  PhoneNumber varchar(15),
  Email varchar(100),
  Address varchar(255),
  HubID int,
  PRIMARY KEY (EmployeeID),
  UNIQUE KEY (PhoneNumber),
  UNIQUE KEY (Email),
  FOREIGN KEY (HubID) REFERENCES hub (HubID)
);

CREATE TABLE shipment (
  TrackingNumber varchar(50) NOT NULL,
  CreatedDate datetime DEFAULT CURRENT_TIMESTAMP,
  CODAmount decimal(15,2) DEFAULT '0.00',
  ShippingFee decimal(15,2) NOT NULL,
  Detail_Address varchar(255),
  LocationID int,
  Sender_ID int,
  Receiver_ID int,
  HubID int,
  Driver_ID int,
  OrderName varchar(255) DEFAULT 'Đơn hàng mới',
  PRIMARY KEY (TrackingNumber),
  FOREIGN KEY (Driver_ID) REFERENCES driver (EmployeeID),
  FOREIGN KEY (HubID) REFERENCES hub (HubID),
  FOREIGN KEY (LocationID) REFERENCES locations (LocationID),
  FOREIGN KEY (Receiver_ID) REFERENCES customer (CustomerID),
  FOREIGN KEY (Sender_ID) REFERENCES customer (CustomerID)
);

CREATE TABLE staff (
  EmployeeID int NOT NULL,
  Role varchar(50),
  PRIMARY KEY (EmployeeID),
  FOREIGN KEY (EmployeeID) REFERENCES personnel (EmployeeID)
);

CREATE TABLE tracking_log (
  LogID int NOT NULL AUTO_INCREMENT,
  UpdateTimestamp datetime DEFAULT CURRENT_TIMESTAMP,
  StatusDescription varchar(255),
  TrackingNumber varchar(50),
  EmployeeID int,
  PRIMARY KEY (LogID),
  FOREIGN KEY (EmployeeID) REFERENCES personnel (EmployeeID),
  FOREIGN KEY (TrackingNumber) REFERENCES shipment (TrackingNumber)
);

CREATE TABLE trucker (
  EmployeeID int NOT NULL,
  LicenseType varchar(20),
  LicensePlate varchar(20),
  PRIMARY KEY (EmployeeID),
  FOREIGN KEY (EmployeeID) REFERENCES driver (EmployeeID),
  FOREIGN KEY (LicensePlate) REFERENCES vehicle (LicensePlate)
);

CREATE TABLE vehicle (
  LicensePlate varchar(20) NOT NULL,
  ManufactureYear int,
  Status varchar(50),
  TypeID int,
  PRIMARY KEY (LicensePlate),
  FOREIGN KEY (TypeID) REFERENCES vehicle_type (TypeID)
);

CREATE TABLE vehicle_type (
  TypeID int NOT NULL AUTO_INCREMENT,
  TypeName varchar(100) NOT NULL,
  MaxPayload decimal(12,2) NOT NULL,
  PRIMARY KEY (TypeID)
);

// tringger
DELIMITER //

CREATE TRIGGER trg_AfterInsertItem AFTER INSERT ON items FOR EACH ROW 
BEGIN
    DECLARE total_extra_fee DECIMAL(15,2);
    -- Tính tổng phí phụ trội của TẤT CẢ các item trong đơn hàng này
    SELECT COALESCE(SUM(CASE WHEN Weight > 5 THEN (Weight - 5) * 5000 ELSE 0 END), 0)
    INTO total_extra_fee
    FROM items WHERE TrackingNumber = NEW.TrackingNumber;

    -- Cập nhật tổng phí = Phí gốc (30k) + Tổng phụ trội
    UPDATE shipment 
    SET ShippingFee = 30000 + total_extra_fee
    WHERE TrackingNumber = NEW.TrackingNumber;
END //

CREATE TRIGGER trg_AfterUpdateItem AFTER UPDATE ON items FOR EACH ROW 
BEGIN
    UPDATE shipment 
    SET ShippingFee = 30000 + (CASE 
                                WHEN NEW.Weight > 5 THEN (NEW.Weight - 5) * 5000 
                                ELSE 0 
                               END)
    WHERE TrackingNumber = NEW.TrackingNumber;
END //

DELIMITER ;

// viem
CREATE VIEW vw_couriertasks AS 
SELECT 
    s.TrackingNumber,
    'Lấy hàng từ khách' AS TaskType,
    c_sender.FullName AS CustomerName,
    c_sender.PhoneNumber AS CustomerPhone,
    c_sender.Detail_Address AS TaskAddress,
    i.NameItem,
    s.CODAmount,
    l_sender.HubID
FROM shipment s 
JOIN items i ON s.TrackingNumber = i.TrackingNumber
JOIN customer c_sender ON s.Sender_ID = c_sender.CustomerID
JOIN locations l_sender ON c_sender.LocationID = l_sender.LocationID
WHERE s.Driver_ID IS NULL AND s.HubID IS NULL 
  AND s.TrackingNumber NOT IN (SELECT TrackingNumber FROM tracking_log WHERE StatusDescription LIKE 'Giao hàng thành công%')
  
UNION ALL 

SELECT 
    s.TrackingNumber,
    'Giao hàng cho khách' AS TaskType,
    c_recv.FullName AS CustomerName,
    c_recv.PhoneNumber AS CustomerPhone,
    s.Detail_Address AS TaskAddress,
    i.NameItem,
    s.CODAmount,
    s.HubID
FROM shipment s 
JOIN items i ON s.TrackingNumber = i.TrackingNumber
JOIN customer c_recv ON s.Receiver_ID = c_recv.CustomerID
JOIN locations l_recv ON s.LocationID = l_recv.LocationID
WHERE s.Driver_ID IS NULL AND s.HubID IS NOT NULL AND s.HubID = l_recv.HubID 
  AND s.TrackingNumber NOT IN (SELECT TrackingNumber FROM tracking_log WHERE StatusDescription LIKE 'Giao hàng thành công%');

CREATE VIEW vw_fullorderdetails AS 
SELECT 
    s.TrackingNumber,
    s.OrderName,
    i.NameItem,
    s.CODAmount,
    s.ShippingFee,
    c_send.FullName AS Sender,
    c_recv.FullName AS Receiver,
    c_recv.Detail_Address AS DeliveryAddress,
    p.FullName AS CurrentDriver,
    p.PhoneNumber AS DriverPhone,
    (SELECT StatusDescription FROM tracking_log WHERE TrackingNumber = s.TrackingNumber ORDER BY LogID DESC LIMIT 1) AS CurrentStatus
FROM shipment s 
JOIN items i ON s.TrackingNumber = i.TrackingNumber
JOIN customer c_send ON s.Sender_ID = c_send.CustomerID
JOIN customer c_recv ON s.Receiver_ID = c_recv.CustomerID
LEFT JOIN personnel p ON s.Driver_ID = p.EmployeeID;

CREATE VIEW vw_hubinventory AS 
SELECT 
    s.TrackingNumber,
    s.OrderName,
    i.NameItem,
    i.Weight,
    s.HubID AS CurrentHubID,
    h_current.HubName AS CurrentHubName,
    c_recv.FullName AS ReceiverName,
    s.Detail_Address AS DeliveryAddress,
    l_recv.Province AS DestinationProvince,
    l_recv.HubID AS DestinationHubID,
    (CASE 
        WHEN s.HubID <> l_recv.HubID THEN 'Chuyển liên tỉnh (Cần Trucker)' 
        WHEN s.HubID = l_recv.HubID THEN 'Giao tận nơi (Cần Courier)' 
        ELSE 'Chưa xác định' 
    END) AS RoutingType
FROM shipment s 
JOIN items i ON s.TrackingNumber = i.TrackingNumber
JOIN customer c_recv ON s.Receiver_ID = c_recv.CustomerID
JOIN locations l_recv ON s.LocationID = l_recv.LocationID
JOIN hub h_current ON s.HubID = h_current.HubID
WHERE s.HubID IS NOT NULL AND s.Driver_ID IS NULL 
  AND s.TrackingNumber NOT IN (SELECT TrackingNumber FROM tracking_log WHERE StatusDescription LIKE 'Giao hàng thành công%');

//Stored Procedures
DELIMITER //

CREATE PROCEDURE sp_CompleteTruckRoute(IN p_DriverID INT)
BEGIN
    UPDATE driver SET Status = 'Sẵn sàng' WHERE EmployeeID = p_DriverID;
    SELECT 'Chuyến đi đã hoàn tất. Trạng thái tài xế: Sẵn sàng!' AS Result;
END //

CREATE PROCEDURE sp_ConfirmInboundHub(IN p_TrackingNumber VARCHAR(50), IN p_DriverID INT)
BEGIN
    DECLARE v_HubID INT;
    DECLARE v_HubName VARCHAR(100);

    SELECT p.HubID, h.HubName INTO v_HubID, v_HubName
    FROM personnel p JOIN hub h ON p.HubID = h.HubID
    WHERE p.EmployeeID = p_DriverID;

    START TRANSACTION;
        UPDATE shipment SET Driver_ID = NULL, HubID = v_HubID WHERE TrackingNumber = p_TrackingNumber;
        UPDATE driver SET Status = 'Sẵn sàng' WHERE EmployeeID = p_DriverID;
        INSERT INTO tracking_log (StatusDescription, TrackingNumber, EmployeeID)
        VALUES (CONCAT('Đã nhập kho - Lưu trữ tại ', v_HubName), p_TrackingNumber, p_DriverID);
    COMMIT;
END //

CREATE PROCEDURE sp_CreateCustomerOrder(
    IN p_TrackingNumber VARCHAR(50), IN p_CODAmount DECIMAL(15,2), IN p_DetailAddress TEXT,
    IN p_LocationID INT, IN p_SenderID INT, IN p_ReceiverID INT, IN p_ItemName VARCHAR(255),
    IN p_ItemWeight DECIMAL(10,2), IN p_Dimensions VARCHAR(50), IN p_ItemType VARCHAR(100)
)
BEGIN
    DECLARE exit handler for sqlexception
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi hệ thống: Không thể tạo đơn hàng.';
    END;

    START TRANSACTION;
        INSERT INTO shipment (TrackingNumber, CODAmount, ShippingFee, Detail_Address, LocationID, Sender_ID, Receiver_ID)
        VALUES (p_TrackingNumber, p_CODAmount, 0.00, p_DetailAddress, p_LocationID, p_SenderID, p_ReceiverID);

        INSERT INTO items (NameItem, TrackingNumber, amounts, Weight, Dimensions, Type)
        VALUES (p_ItemName, p_TrackingNumber, 1, p_ItemWeight, p_Dimensions, p_ItemType);
    COMMIT;
    
    SELECT 'Đơn hàng đã được tạo thành công!' AS Message, p_TrackingNumber AS TrackingID;
END //

CREATE PROCEDURE sp_DeliverySuccess(IN p_TrackingNumber VARCHAR(50), IN p_DriverID INT)
BEGIN
    START TRANSACTION;
        UPDATE driver SET Status = 'Sẵn sàng' WHERE EmployeeID = p_DriverID;
        UPDATE shipment SET Driver_ID = NULL WHERE TrackingNumber = p_TrackingNumber;
        INSERT INTO tracking_log (StatusDescription, TrackingNumber, EmployeeID)
        VALUES ('Giao hàng thành công - Người nhận đã ký xác nhận', p_TrackingNumber, p_DriverID);
    COMMIT;
END //

CREATE PROCEDURE sp_DispatchTruck(IN p_DriverID INT)
BEGIN
    UPDATE driver SET Status = 'Đang đi giao' WHERE EmployeeID = p_DriverID;
    SELECT 'Hoàn tất xếp hàng. Xe tải đã chính thức khởi hành!' AS Message;
END //

CREATE PROCEDURE sp_DriverAcceptOrder(IN p_TrackingNumber VARCHAR(50), IN p_DriverID INT)
BEGIN
    DECLARE v_HubName VARCHAR(100);
    SELECT h.HubName INTO v_HubName FROM personnel p JOIN hub h ON p.HubID = h.HubID WHERE p.EmployeeID = p_DriverID;

    START TRANSACTION;
        UPDATE shipment SET Driver_ID = p_DriverID WHERE TrackingNumber = p_TrackingNumber;
        UPDATE driver SET Status = 'Đang đi giao' WHERE EmployeeID = p_DriverID;
        INSERT INTO tracking_log (StatusDescription, TrackingNumber, EmployeeID)
        VALUES (CONCAT('Shipper đã nhận - Đang chuyển về ', v_HubName), p_TrackingNumber, p_DriverID);
    COMMIT;
    SELECT CONCAT('Tài xế đã tiếp nhận đơn. Trạng thái tài xế: Đang đi giao.') AS Result;
END //

CREATE PROCEDURE sp_DriverDeliveryOutbound(IN p_TrackingNumber VARCHAR(50), IN p_DriverID INT)
BEGIN
    DECLARE v_DeliveryAddress TEXT;
    SELECT Detail_Address INTO v_DeliveryAddress FROM shipment WHERE TrackingNumber = p_TrackingNumber;

    IF v_DeliveryAddress IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Không tìm thấy đơn hàng.';
    END IF;

    START TRANSACTION;
        UPDATE shipment SET Driver_ID = p_DriverID, HubID = NULL WHERE TrackingNumber = p_TrackingNumber;
        UPDATE driver SET Status = 'Đang đi giao' WHERE EmployeeID = p_DriverID;
        INSERT INTO tracking_log (StatusDescription, TrackingNumber, EmployeeID)
        VALUES (CONCAT('Đang giao tới địa chỉ: ', v_DeliveryAddress), p_TrackingNumber, p_DriverID);
    COMMIT;
    SELECT CONCAT('Thành công! Tài xế đã lấy hàng khỏi kho. Đang giao tới: ', v_DeliveryAddress) AS Result;
END //

CREATE PROCEDURE sp_LoadToTruck(IN p_TrackingNumber VARCHAR(50), IN p_DriverID INT)
BEGIN
    DECLARE v_DestHubName VARCHAR(100);
    DECLARE v_ItemWeight DECIMAL(10,2);
    DECLARE v_CurrentLoad DECIMAL(10,2);
    DECLARE v_MaxCapacity DECIMAL(12,2);

    SELECT h.HubName INTO v_DestHubName FROM shipment s JOIN locations l ON s.LocationID = l.LocationID JOIN hub h ON l.HubID = h.HubID WHERE s.TrackingNumber = p_TrackingNumber;
    SELECT Weight INTO v_ItemWeight FROM items WHERE TrackingNumber = p_TrackingNumber;
    
    SELECT COALESCE(SUM(i.Weight), 0) INTO v_CurrentLoad FROM shipment s JOIN items i ON s.TrackingNumber = i.TrackingNumber WHERE s.Driver_ID = p_DriverID;

    SELECT vt.MaxPayload INTO v_MaxCapacity FROM trucker t JOIN vehicle v ON t.LicensePlate = v.LicensePlate JOIN vehicle_type vt ON v.TypeID = vt.TypeID WHERE t.EmployeeID = p_DriverID;

    IF (v_CurrentLoad + v_ItemWeight) > v_MaxCapacity THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'LỖI: Vượt quá tải trọng cho phép của xe tải!';
    END IF;

    START TRANSACTION;
        UPDATE shipment SET Driver_ID = p_DriverID, HubID = NULL WHERE TrackingNumber = p_TrackingNumber;
        INSERT INTO tracking_log (StatusDescription, TrackingNumber, EmployeeID)
        VALUES (CONCAT('Đã xuất kho - Đang luân chuyển liên tỉnh tới ', v_DestHubName), p_TrackingNumber, p_DriverID);
    COMMIT;
    SELECT CONCAT('Thành công! Đã xếp hàng lên xe. Tải trọng: ', (v_CurrentLoad + v_ItemWeight), '/', v_MaxCapacity, ' kg') AS Result;
END //

CREATE PROCEDURE sp_ReceiveFromTrucker(IN p_TrackingNumber VARCHAR(50), IN p_StaffID INT)
BEGIN
    DECLARE v_StaffHubID INT; DECLARE v_StaffHubName VARCHAR(100);
    DECLARE v_DestHubID INT; DECLARE v_DestHubName VARCHAR(100);

    SELECT p.HubID, h.HubName INTO v_StaffHubID, v_StaffHubName FROM personnel p JOIN hub h ON p.HubID = h.HubID WHERE p.EmployeeID = p_StaffID;
    SELECT l.HubID, h.HubName INTO v_DestHubID, v_DestHubName FROM shipment s JOIN locations l ON s.LocationID = l.LocationID JOIN hub h ON l.HubID = h.HubID WHERE s.TrackingNumber = p_TrackingNumber;

    IF v_StaffHubID <> v_DestHubID THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'LOI: Don hang nay di kho khac. Vui long de lai tren xe!';
    END IF;

    START TRANSACTION;
        UPDATE shipment SET Driver_ID = NULL, HubID = v_StaffHubID WHERE TrackingNumber = p_TrackingNumber;
        INSERT INTO tracking_log (StatusDescription, TrackingNumber, EmployeeID)
        VALUES (CONCAT('Đã nhập kho đích - Đang xử lý tại ', v_StaffHubName), p_TrackingNumber, p_StaffID);
    COMMIT;
    SELECT CONCAT('Thành công! Đã dỡ đơn hàng khỏi xe tải và nhập vào ', v_StaffHubName) AS Result;
END //

DELIMITER ;
