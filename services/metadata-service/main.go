package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/PuerkitoBio/goquery"
	"golang.org/x/net/html"
)

type MetadataService struct {
	cache      *Cache
	httpClient *http.Client
	mu         sync.RWMutex
}

type Cache struct {
	items map[string]*CacheItem
	mu    sync.RWMutex
}

type CacheItem struct {
	Metadata  *URLMetadata
	ExpiresAt time.Time
}

type URLMetadata struct {
	URL         string `json:"url"`
	Title       string `json:"title"`
	Description string `json:"description"`
	SiteName    string `json:"site_name,omitempty"`
	ImageURL    string `json:"image_url,omitempty"`
	Error       string `json:"error,omitempty"`
}

type FetchRequest struct {
	URL string `json:"url"`
}

type FetchResponse struct {
	Metadata *URLMetadata `json:"metadata"`
	Cached   bool         `json:"cached"`
}

func NewMetadataService() *MetadataService {
	return &MetadataService{
		cache: &Cache{
			items: make(map[string]*CacheItem),
		},
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     30 * time.Second,
			},
		},
	}
}

func (c *Cache) Get(url string) (*URLMetadata, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	item, exists := c.items[url]
	if !exists {
		return nil, false
	}

	if time.Now().After(item.ExpiresAt) {
		delete(c.items, url)
		return nil, false
	}

	return item.Metadata, true
}

func (c *Cache) Set(url string, metadata *URLMetadata, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.items[url] = &CacheItem{
		Metadata:  metadata,
		ExpiresAt: time.Now().Add(ttl),
	}
}

func (c *Cache) Cleanup() {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	for url, item := range c.items {
		if now.After(item.ExpiresAt) {
			delete(c.items, url)
		}
	}
}

func (ms *MetadataService) fetchMetadata(ctx context.Context, url string) (*URLMetadata, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Lobsters-MetadataService/1.0")
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	req.Header.Set("Accept-Language", "en-US,en;q=0.5")

	resp, err := ms.httpClient.Do(req)
	if err != nil {
		return &URLMetadata{
			URL:   url,
			Error: fmt.Sprintf("failed to fetch: %v", err),
		}, nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return &URLMetadata{
			URL:   url,
			Error: fmt.Sprintf("HTTP %d", resp.StatusCode),
		}, nil
	}

	doc, err := goquery.NewDocumentFromReader(resp.Body)
	if err != nil {
		return &URLMetadata{
			URL:   url,
			Error: fmt.Sprintf("failed to parse HTML: %v", err),
		}, nil
	}

	metadata := &URLMetadata{
		URL: url,
	}

	metadata.Title = ms.extractTitle(doc)
	metadata.Description = ms.extractDescription(doc)
	metadata.SiteName = ms.extractSiteName(doc)
	metadata.ImageURL = ms.extractImageURL(doc)

	if metadata.URL == "" {
		metadata.URL = url
	}

	return metadata, nil
}

func (ms *MetadataService) extractTitle(doc *goquery.Document) string {
	ogTitle := doc.Find("meta[property='og:title']").AttrOr("content", "")
	if ogTitle != "" {
		return cleanTitle(ogTitle)
	}

	metaTitle := doc.Find("meta[name='title']").AttrOr("content", "")
	if metaTitle != "" {
		return cleanTitle(metaTitle)
	}

	title := doc.Find("title").Text()
	return cleanTitle(title)
}

func (ms *MetadataService) extractDescription(doc *goquery.Document) string {
	ogDesc := doc.Find("meta[property='og:description']").AttrOr("content", "")
	if ogDesc != "" {
		return ogDesc
	}

	metaDesc := doc.Find("meta[name='description']").AttrOr("content", "")
	if metaDesc != "" {
		return metaDesc
	}

	firstP := doc.Find("p").First().Text()
	if len(firstP) > 300 {
		return firstP[:300] + "..."
	}
	return firstP
}

func (ms *MetadataService) extractSiteName(doc *goquery.Document) string {
	return doc.Find("meta[property='og:site_name']").AttrOr("content", "")
}

func (ms *MetadataService) extractImageURL(doc *goquery.Document) string {
	return doc.Find("meta[property='og:image']").AttrOr("content", "")
}

func cleanTitle(title string) string {
	title = html.UnescapeString(title)
	title = trimSpace(title)

	if len(title) > 150 {
		title = title[:150]
	}

	title = removeGitHubPrefix(title)

	return title
}

func removeGitHubPrefix(title string) string {
	prefix := "GitHub - "
	if len(title) > len(prefix) && title[:len(prefix)] == prefix {
		title = title[len(prefix):]
		if idx := indexOf(title, "/"); idx > 0 && idx < 40 {
			title = title[idx+1:]
		}
	}
	return title
}

func indexOf(s string, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}

func trimSpace(s string) string {
	start := 0
	for start < len(s) && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n') {
		start++
	}
	end := len(s)
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n') {
		end--
	}
	return s[start:end]
}

func (ms *MetadataService) handleFetch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req FetchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid request: %v", err), http.StatusBadRequest)
		return
	}

	if req.URL == "" {
		http.Error(w, "URL is required", http.StatusBadRequest)
		return
	}

	cached, found := ms.cache.Get(req.URL)
	if found {
		json.NewEncoder(w).Encode(FetchResponse{
			Metadata: cached,
			Cached:   true,
		})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	metadata, err := ms.fetchMetadata(ctx, req.URL)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to fetch metadata: %v", err), http.StatusInternalServerError)
		return
	}

	ms.cache.Set(req.URL, metadata, 24*time.Hour)

	json.NewEncoder(w).Encode(FetchResponse{
		Metadata: metadata,
		Cached:   false,
	})
}

func (ms *MetadataService) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "healthy",
		"service": "metadata-service",
	})
}

func (ms *MetadataService) startCacheCleanup() {
	ticker := time.NewTicker(1 * time.Hour)
	go func() {
		for range ticker.C {
			ms.cache.Cleanup()
		}
	}()
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	service := NewMetadataService()
	service.startCacheCleanup()

	mux := http.NewServeMux()
	mux.HandleFunc("/fetch", service.handleFetch)
	mux.HandleFunc("/health", service.handleHealth)

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		log.Printf("Metadata service starting on port %s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}
