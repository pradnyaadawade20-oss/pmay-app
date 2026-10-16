package mailer

import (
	"crypto/tls"
	"fmt"
	"mime"
	"net"
	"net/mail"
	"net/smtp"
	"pmay-backend/internal/config"
	"strings"
	"time"
)

// Send sends one HTML email through the configured SMTP server.
// Port 465 = implicit TLS, anything else (587) = STARTTLS.
// NOTE: Render blocks outbound SMTP ports on FREE web services; a paid instance is required.
func Send(cfg config.Config, to, subject, htmlBody string) error {
	port := cfg.SMTPPort
	if port == "" {
		port = "587"
	}
	addr := net.JoinHostPort(cfg.SMTPHost, port)
	tlsCfg := &tls.Config{ServerName: cfg.SMTPHost}
	d := &net.Dialer{Timeout: 15 * time.Second}

	var conn net.Conn
	var err error
	if port == "465" {
		conn, err = tls.DialWithDialer(d, "tcp", addr, tlsCfg)
	} else {
		conn, err = d.Dial("tcp", addr)
	}
	if err != nil {
		return fmt.Errorf("smtp connect %s: %w", addr, err)
	}
	_ = conn.SetDeadline(time.Now().Add(30 * time.Second))

	c, err := smtp.NewClient(conn, cfg.SMTPHost)
	if err != nil {
		conn.Close()
		return fmt.Errorf("smtp client: %w", err)
	}
	defer c.Close()

	if port != "465" {
		if ok, _ := c.Extension("STARTTLS"); !ok {
			return fmt.Errorf("smtp server does not support STARTTLS")
		}
		if err := c.StartTLS(tlsCfg); err != nil {
			return fmt.Errorf("smtp starttls: %w", err)
		}
	}
	if err := c.Auth(smtp.PlainAuth("", cfg.SMTPUser, cfg.SMTPPass, cfg.SMTPHost)); err != nil {
		return fmt.Errorf("smtp auth: %w", err)
	}

	from := cfg.SMTPFrom
	if from == "" {
		from = "PMAY Registration <" + cfg.SMTPUser + ">"
	}
	fromAddr, err := mail.ParseAddress(from)
	if err != nil {
		return fmt.Errorf("SMTP_FROM invalid: %w", err)
	}
	if err := c.Mail(fromAddr.Address); err != nil {
		return err
	}
	if err := c.Rcpt(to); err != nil {
		return err
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	msg := strings.Join([]string{
		"From: " + fromAddr.String(),
		"To: " + to,
		"Subject: " + mime.QEncoding.Encode("utf-8", subject),
		"Date: " + time.Now().Format(time.RFC1123Z),
		"MIME-Version: 1.0",
		"Content-Type: text/html; charset=UTF-8",
		"",
		htmlBody,
	}, "\r\n")
	if _, err := w.Write([]byte(msg)); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return c.Quit()
}
