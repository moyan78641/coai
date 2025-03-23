package auth

import (
	"chat/utils"
	"../xunhupay-master"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"
	"net/http"
	"strconv"
	"time"
)

// XunhuPayConfig 虎皮椒支付配置
type XunhuPayConfig struct {
	AppID     string `json:"app_id"`
	AppSecret string `json:"app_secret"`
	PayURL    string `json:"pay_url"`
	QueryURL  string `json:"query_url"`
	NotifyURL string `json:"notify_url"`
	ReturnURL string `json:"return_url"`
	WapName   string `json:"wap_name"`
}

// XunhuPayResponse 虎皮椒支付响应
type XunhuPayResponse struct {
	Status bool   `json:"status"`
	URL    string `json:"url"`
	Msg    string `json:"msg"`
}

// XunhuPayNotifyRequest 虎皮椒支付回调请求
type XunhuPayNotifyRequest struct {
	AppID         string `form:"appid" json:"appid"`
	TradeOrderID  string `form:"trade_order_id" json:"trade_order_id"`
	OutTradeOrder string `form:"out_trade_order" json:"out_trade_order"`
	Status        string `form:"status" json:"status"`
	PayType       string `form:"pay_type" json:"pay_type"`
	TotalFee      string `form:"total_fee" json:"total_fee"`
	TransactionID string `form:"transaction_id" json:"transaction_id"`
	OpenID        string `form:"openid" json:"openid"`
	MchID         string `form:"mch_id" json:"mch_id"`
	IsSubscribe   string `form:"is_subscribe" json:"is_subscribe"`
	Time          string `form:"time" json:"time"`
	NonceStr      string `form:"nonce_str" json:"nonce_str"`
	Hash          string `form:"hash" json:"hash"`
}

// GetXunhuPayConfig 获取虎皮椒支付配置
func GetXunhuPayConfig() XunhuPayConfig {
	return XunhuPayConfig{
		AppID:     viper.GetString("payment.xunhupay.app_id"),
		AppSecret: viper.GetString("payment.xunhupay.app_secret"),
		PayURL:    viper.GetString("payment.xunhupay.pay_url"),
		QueryURL:  viper.GetString("payment.xunhupay.query_url"),
		NotifyURL: viper.GetString("payment.xunhupay.notify_url"),
		ReturnURL: viper.GetString("payment.xunhupay.return_url"),
		WapName:   viper.GetString("payment.xunhupay.wap_name"),
	}
}

// XunhuPay 虎皮椒支付
func XunhuPay(username string, quota int) (XunhuPayResponse, error) {
	config := GetXunhuPayConfig()
	
	// 检查配置是否完整
	if config.AppID == "" || config.AppSecret == "" || config.PayURL == "" {
		return XunhuPayResponse{Status: false, Msg: "支付配置不完整"}, errors.New("支付配置不完整")
	}
	
	// 创建订单号
	orderID := GenerateOrder()
	
	// 计算金额
	amount := float32(quota) * 0.1
	
	// 初始化虎皮椒客户端
	client := xunhupay.NewHuPi(&config.AppID, &config.AppSecret)
	
	// 构建支付参数
	params := map[string]string{
		"version":        "1.1",
		"trade_order_id": orderID,
		"total_fee":      fmt.Sprintf("%.2f", amount),
		"title":          fmt.Sprintf("购买%d点数", quota),
		"notify_url":     config.NotifyURL,
		"return_url":     config.ReturnURL,
		"wap_name":       config.WapName,
	}
	
	// 执行支付请求
	result, err := client.Execute(config.PayURL, params)
	if err != nil {
		return XunhuPayResponse{Status: false, Msg: err.Error()}, err
	}
	
	// 解析响应
	response, err := utils.Unmarshal[map[string]interface{}]([]byte(result))
	if err != nil {
		return XunhuPayResponse{Status: false, Msg: "解析支付响应失败"}, err
	}
	
	// 检查支付响应状态
	if status, ok := response["status"]; !ok || status.(bool) != true {
		msg := "支付请求失败"
		if errMsg, ok := response["err_msg"]; ok {
			msg = errMsg.(string)
		}
		return XunhuPayResponse{Status: false, Msg: msg}, errors.New(msg)
	}
	
	// 获取支付URL
	payURL, ok := response["url"]
	if !ok {
		return XunhuPayResponse{Status: false, Msg: "获取支付URL失败"}, errors.New("获取支付URL失败")
	}
	
	return XunhuPayResponse{Status: true, URL: payURL.(string)}, nil
}

// XunhuPayAPI 虎皮椒支付API
func XunhuPayAPI(c *gin.Context) {
	// 获取用户信息
	user := GetUserFromContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": false, "message": "未授权"})
		return
	}
	
	// 获取购买点数
	quota, err := strconv.Atoi(c.PostForm("quota"))
	if err != nil || quota <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"status": false, "message": "无效的点数"})
		return
	}
	
	// 执行支付
	response, err := XunhuPay(user.Username, quota)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": false, "message": response.Msg})
		return
	}
	
	c.JSON(http.StatusOK, response)
}

// XunhuPayNotifyAPI 虎皮椒支付回调API
func XunhuPayNotifyAPI(c *gin.Context) {
	// 获取回调参数
	var request XunhuPayNotifyRequest
	if err := c.ShouldBind(&request); err != nil {
		c.String(http.StatusBadRequest, "FAIL")
		return
	}
	
	// 获取配置
	config := GetXunhuPayConfig()
	
	// 验证签名
	client := xunhupay.NewHuPi(&config.AppID, &config.AppSecret)
	params := map[string]string{
		"appid":          request.AppID,
		"trade_order_id": request.TradeOrderID,
		"out_trade_order": request.OutTradeOrder,
		"status":        request.Status,
		"pay_type":      request.PayType,
		"total_fee":     request.TotalFee,
		"transaction_id": request.TransactionID,
		"openid":        request.OpenID,
		"mch_id":        request.MchID,
		"is_subscribe":  request.IsSubscribe,
		"time":          request.Time,
		"nonce_str":     request.NonceStr,
	}
	
	// 计算签名
	sign := client.Sign(params)
	if sign != request.Hash {
		c.String(http.StatusBadRequest, "FAIL")
		return
	}
	
	// 检查支付状态
	if request.Status != "1" {
		c.String(http.StatusOK, "SUCCESS")
		return
	}
	
	// 解析订单号和用户名
	orderID := request.TradeOrderID
	
	// 解析金额
	totalFee, err := strconv.ParseFloat(request.TotalFee, 32)
	if err != nil {
		c.String(http.StatusBadRequest, "FAIL")
		return
	}
	
	// 计算点数
	quota := int(float32(totalFee) * 10)
	
	// 查询订单是否已处理
	// TODO: 实现订单查询逻辑
	
	// 处理订单
	// TODO: 实现订单处理逻辑，增加用户点数
	
	c.String(http.StatusOK, "SUCCESS")
}

// XunhuPayQueryAPI 虎皮椒支付查询API
func XunhuPayQueryAPI(c *gin.Context) {
	// 获取用户信息
	user := GetUserFromContext(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"status": false, "message": "未授权"})
		return
	}
	
	// 获取订单号
	orderID := c.Query("order_id")
	if orderID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"status": false, "message": "订单号不能为空"})
		return
	}
	
	// 获取配置
	config := GetXunhuPayConfig()
	
	// 初始化虎皮椒客户端
	client := xunhupay.NewHuPi(&config.AppID, &config.AppSecret)
	
	// 构建查询参数
	params := map[string]string{
		"out_trade_order": orderID,
	}
	
	// 执行查询请求
	result, err := client.Execute(config.QueryURL, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": false, "message": err.Error()})
		return
	}
	
	// 解析响应
	response, err := utils.Unmarshal[map[string]interface{}]([]byte(result))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"status": false, "message": "解析查询响应失败"})
		return
	}
	
	c.JSON(http.StatusOK, response)
}
