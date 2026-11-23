package handlers

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/url"

	"github.com/yehudahason/andromeda-forumV2/backend/internal/auth"
	"github.com/yehudahason/andromeda-forumV2/backend/internal/storage"
)

func (h *Handler) UploadImageHandler(w http.ResponseWriter, r *http.Request) {
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

	imageURL, err := storage.UploadImageToR2(
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

func (h *Handler) UpdateProfileImage(
	w http.ResponseWriter,
	r *http.Request,
) {
	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error("authentication error", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var input struct {
		ImageURL string `json:"image_url"`
	}

	r.Body = http.MaxBytesReader(w, r.Body, 4096)

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Validate image URL (empty string removes the image).
	if input.ImageURL != "" {
		u, err := url.Parse(input.ImageURL)

		if err != nil ||
			(u.Scheme != "http" && u.Scheme != "https") ||
			u.Host == "" {
			http.Error(w, "Invalid image URL", http.StatusBadRequest)
			return
		}
	}

	const query = `
		UPDATE public.profiles
		SET
			image_url = $1,
			updated_at = NOW()
		WHERE auth_user_id = $2
	`

	result, err := h.DB.Exec(
		r.Context(),
		query,
		input.ImageURL,
		user.ID,
	)

	if err != nil {
		h.Logger.Error(
			"failed to update profile image",
			"error", err,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	if result.RowsAffected() == 0 {
		http.Error(w, "Profile not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	json.NewEncoder(w).Encode(map[string]string{
		"image_url": input.ImageURL,
	})
}
