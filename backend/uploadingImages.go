package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

var (
	r2Client  *s3.Client
	r2Once    sync.Once
	r2InitErr error
)

func uploadImageToR2(
	ctx context.Context,
	folder string,
	data []byte,
	contentType string,
) (string, error) {

	client, err := getR2Client(ctx)
	if err != nil {
		return "", err
	}

	var ext string

	switch contentType {
	case "image/jpeg":
		ext = ".jpg"
	case "image/png":
		ext = ".png"
	case "image/webp":
		ext = ".webp"
	case "image/gif":
		ext = ".gif"
	default:
		return "", fmt.Errorf(
			"unsupported image type: %s",
			contentType,
		)
	}

	filename := uuid.NewString() + ext

	key := fmt.Sprintf(
		"%s/%s",
		strings.Trim(folder, "/"),
		filename,
	)

	_, err = client.PutObject(
		ctx,
		&s3.PutObjectInput{
			Bucket: aws.String(
				os.Getenv("R2_BUCKET"),
			),
			Key:  aws.String(key),
			Body: bytes.NewReader(data),
			ContentType: aws.String(
				contentType,
			),
			CacheControl: aws.String(
				"public, max-age=31536000, immutable",
			),
		},
	)
	if err != nil {
		return "", fmt.Errorf(
			"upload image to R2: %w",
			err,
		)
	}

	publicURL := strings.TrimRight(
		os.Getenv("R2_PUBLIC_URL"),
		"/",
	)

	return publicURL + "/" + key, nil
}

func uploadImageHandler(w http.ResponseWriter, r *http.Request) {
	err := r.ParseMultipartForm(5 << 20) // 5 MB
	if err != nil {
		http.Error(w, "Invalid upload", http.StatusBadRequest)
		return
	}

	file, _, err := r.FormFile("image")
	if err != nil {
		http.Error(w, "Image required", http.StatusBadRequest)
		return
	}
	defer file.Close()

	data, err := io.ReadAll(
		io.LimitReader(file, (5<<20)+1),
	)
	if err != nil {
		http.Error(w, "Failed to read image", 500)
		return
	}

	if len(data) > 5<<20 {
		http.Error(
			w,
			"Image too large",
			http.StatusRequestEntityTooLarge,
		)
		return
	}

	contentType := http.DetectContentType(data)

	imageURL, err := uploadImageToR2(
		r.Context(),
		"forum",
		data,
		contentType,
	)
	if err != nil {
		log.Printf("R2 upload error: %v", err)

		http.Error(
			w,
			"Upload failed",
			http.StatusInternalServerError,
		)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	json.NewEncoder(w).Encode(map[string]string{
		"url": imageURL,
	})
}
func getR2Client(ctx context.Context) (*s3.Client, error) {
	r2Once.Do(func() {
		accessKey := os.Getenv("R2_ACCESS_KEY_ID")
		secretKey := os.Getenv("R2_SECRET_ACCESS_KEY")
		endpoint := os.Getenv("R2_ENDPOINT")

		if accessKey == "" ||
			secretKey == "" ||
			endpoint == "" {
			r2InitErr = errors.New("missing R2 environment variables")
			return
		}

		cfg, err := config.LoadDefaultConfig(
			ctx,
			config.WithRegion("auto"),
			config.WithCredentialsProvider(
				credentials.NewStaticCredentialsProvider(
					accessKey,
					secretKey,
					"",
				),
			),
		)
		if err != nil {
			r2InitErr = fmt.Errorf(
				"load R2 config: %w",
				err,
			)
			return
		}

		r2Client = s3.NewFromConfig(
			cfg,
			func(o *s3.Options) {
				o.BaseEndpoint = aws.String(endpoint)
			},
		)
	})

	if r2InitErr != nil {
		return nil, r2InitErr
	}

	return r2Client, nil
}

func uploadAvatarToR2(
	ctx context.Context,
	userID uuid.UUID,
	imageURL string,
) (string, error) {

	imageURL = strings.TrimSpace(imageURL)

	if imageURL == "" {
		return "", nil
	}

	publicBaseURL := strings.TrimRight(
		os.Getenv("R2_PUBLIC_URL"),
		"/",
	)

	// Already using our R2 image.
	if publicBaseURL != "" &&
		strings.HasPrefix(imageURL, publicBaseURL+"/") {
		return imageURL, nil
	}

	// Only copy HTTPS images.
	parsedURL, err := url.Parse(imageURL)
	if err != nil {
		return "", fmt.Errorf("invalid avatar URL: %w", err)
	}

	if parsedURL.Scheme != "https" {
		return "", errors.New("avatar URL must use HTTPS")
	}

	// Since this is for Google avatars, don't allow arbitrary URLs
	// from the database to make your server request arbitrary hosts.
	// host := strings.ToLower(parsedURL.Hostname())

	// if host != "googleusercontent.com" &&
	// 	!strings.HasSuffix(host, ".googleusercontent.com") {
	// 	return "", fmt.Errorf(
	// 		"unsupported avatar host: %s",
	// 		host,
	// 	)
	// }

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodGet,
		imageURL,
		nil,
	)
	if err != nil {
		return "", fmt.Errorf(
			"create avatar request: %w",
			err,
		)
	}

	req.Header.Set(
		"Accept",
		"image/avif,image/webp,image/png,image/jpeg,image/*",
	)

	httpClient := &http.Client{
		Timeout: 10 * time.Second,
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf(
			"download avatar: %w",
			err,
		)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf(
			"avatar server returned %s",
			resp.Status,
		)
	}

	const maxAvatarSize = 5 << 20 // 5 MiB

	data, err := io.ReadAll(
		io.LimitReader(
			resp.Body,
			maxAvatarSize+1,
		),
	)
	if err != nil {
		return "", fmt.Errorf(
			"read avatar: %w",
			err,
		)
	}

	if len(data) > maxAvatarSize {
		return "", errors.New("avatar is larger than 5 MiB")
	}

	if len(data) == 0 {
		return "", errors.New("empty avatar")
	}

	contentType := http.DetectContentType(data)

	switch contentType {
	case "image/jpeg",
		"image/png",
		"image/webp",
		"image/gif",
		"image/avif":
		// allowed
	default:
		return "", fmt.Errorf(
			"unsupported avatar content type: %s",
			contentType,
		)
	}

	client, err := getR2Client(ctx)
	if err != nil {
		return "", err
	}

	// No extension is required.
	// The Content-Type tells the browser what the object is.
	key := fmt.Sprintf(
		"avatars/%s",
		userID.String(),
	)

	_, err = client.PutObject(
		ctx,
		&s3.PutObjectInput{
			Bucket: aws.String(
				os.Getenv("R2_BUCKET"),
			),

			Key: aws.String(key),

			Body: bytes.NewReader(data),

			ContentType: aws.String(
				contentType,
			),

			CacheControl: aws.String(
				"public, max-age=3600",
			),
		},
	)
	if err != nil {
		return "", fmt.Errorf(
			"upload avatar to R2: %w",
			err,
		)
	}

	if publicBaseURL == "" {
		return "", errors.New(
			"R2_PUBLIC_URL is missing",
		)
	}

	return publicBaseURL + "/" + key, nil
}
