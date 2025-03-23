-- 创建支付记录表
CREATE TABLE IF NOT EXISTS payment_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(64) NOT NULL COMMENT '订单号',
    username VARCHAR(64) NOT NULL COMMENT '用户名',
    amount FLOAT NOT NULL COMMENT '支付金额',
    quota INT NOT NULL COMMENT '购买点数',
    created_at BIGINT NOT NULL COMMENT '创建时间',
    UNIQUE KEY (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;