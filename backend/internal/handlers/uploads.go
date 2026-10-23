package handlers

import (
	"encoding/json"
	"io"
	"log"
	"net/http"

	"github.com/yehudahason/andromeda-forumV2/internal/storage"
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
