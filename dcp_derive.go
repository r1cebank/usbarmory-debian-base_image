// NXP Data Co-Processor (DCP) key derive tool
//  based on https://github.com/f-secure-foundry/mxs-dcp
//
// Copyright (c) r1cebank
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation under version 3 of the License.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
// more details.
//
// See accompanying LICENSE file for full details.
//
// IMPORTANT: the unique OTPMK internal key is available only when Secure Boot
// (HAB) is enabled, otherwise a Non-volatile Test Key (NVTK), identical for
// each SoC, is used. The secure operation of the DCP and SNVS, in production
// deployments, should always be paired with Secure Boot activation.
//
//+build linux

package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"syscall"
	"unsafe"

	"golang.org/x/sys/unix"
)

// Symmetric file encryption using AES-128-OFB, key is derived from a known
// diversifier encrypted with AES-128-CBC through the NXP Data Co-Processor
// (DCP) with its device specific secret key. This uniquely ties the derived
// key to the specific hardware unit being used.
//
// The initialization vector is prepended to the encrypted file, the HMAC for
// authentication is appended:
//
// iv (16 bytes) || ciphertext || hmac (32 bytes)

type af_alg_iv struct {
	ivlen uint32
	iv    [aes.BlockSize]byte
}

// NIST AES-128-CBC test vector
const TEST_KEY = "\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c"

var test bool

func init() {
	log.SetFlags(0)
	log.SetOutput(os.Stdout)

	flag.BoolVar(&test, "t", false, "test mode (skcipher cbc(aes) w/ test key)")

	flag.Usage = func() {
		log.Println("usage: [enc|dec] [cleartext] [diversifier]")
	}
}

func main() {
	var err error

	var inputString string

	flag.Parse()

	if len(flag.Args()) != 3 {
		flag.Usage()
		os.Exit(1)
	}

	op := flag.Arg(0)

	switch op {
	case "enc":
		inputString = flag.Arg(1)
	case "dec":
		inputString = flag.Arg(1)
	default:
		log.Fatal("dcp_tool: error, invalid operation")
	}

	defer func() {
		if err != nil {
			log.Fatalf("dcp_tool: error, %v", err)
		}
	}()

	diversifier, err := hex.DecodeString(flag.Arg(2))

	if err != nil {
		return
	}

	if len(diversifier) > 1 {
		log.Fatalf("dcp_tool: error, diversifier must be a single byte value in hex format (e.g. ab)")
	}

	switch op {
	case "enc":
		result := encrypt(inputString, diversifier)
		fmt.Printf("%s", result)
	case "dec":
		result := decrypt(inputString, diversifier)
		fmt.Printf("%s", result)
	}
}

func encrypt(inputString string, diversifier []byte) (result string) {
	// It is advised to use only deterministic input data for key
	// derivation, therefore we use the empty allocated IV before it being
	// filled.
	iv := make([]byte, aes.BlockSize)
	key, err := DCPDeriveKey(diversifier, iv)

	if err != nil {
		return
	}

	if err != nil {
		return
	}

	result, err = encryptString(key, inputString)

	return result
}

func decrypt(inputString string, diversifier []byte) (result string) {
	// It is advised to use only deterministic input data for key
	// derivation, therefore we use the empty allocated IV before it being
	// filled.
	iv := make([]byte, aes.BlockSize)
	key, err := DCPDeriveKey(diversifier, iv)

	if err != nil {
		return
	}

	if err != nil {
		return
	}

	result, err = decryptString(key, inputString)

	return result
}

// equivalent to PKCS#11 C_DeriveKey with CKM_AES_CBC_ENCRYPT_DATA
func DCPDeriveKey(diversifier []byte, iv []byte) (key []byte, err error) {
	log.Printf("dcp_tool: deriving key, diversifier %x", diversifier)

	fd, err := unix.Socket(unix.AF_ALG, unix.SOCK_SEQPACKET, 0)

	if err != nil {
		return
	}
	defer unix.Close(fd)

	addr := &unix.SockaddrALG{
		Type: "skcipher",
		Name: "cbc-aes-dcp",
	}

	if test {
		addr.Type = "skcipher"
		addr.Name = "cbc(aes)"
	}

	err = unix.Bind(fd, addr)

	if err != nil {
		return
	}

	if test {
		err = syscall.SetsockoptString(fd, unix.SOL_ALG, unix.ALG_SET_KEY, TEST_KEY)
	} else {
		// https://github.com/golang/go/issues/31277
		// SetsockoptString does not allow empty strings
		_, _, e1 := syscall.Syscall6(syscall.SYS_SETSOCKOPT, uintptr(fd), uintptr(unix.SOL_ALG), uintptr(unix.ALG_SET_KEY), uintptr(0), uintptr(0), 0)

		if e1 != 0 {
			err = errors.New("setsockopt failed")
			return
		}
	}

	if err != nil {
		return
	}

	apifd, _, _ := unix.Syscall(unix.SYS_ACCEPT, uintptr(fd), 0, 0)

	return cryptoAPI(apifd, unix.ALG_OP_ENCRYPT, iv, pad(diversifier, false))
}

func encryptString(key []byte, message string) (encmess string, err error) {
	plainText := []byte(message)

	block, err := aes.NewCipher(key)
	if err != nil {
		return
	}

	//IV needs to be unique, but doesn't have to be secure.
	//It's common to put it at the beginning of the ciphertext.
	cipherText := make([]byte, aes.BlockSize+len(plainText))
	iv := cipherText[:aes.BlockSize]
	if _, err = io.ReadFull(rand.Reader, iv); err != nil {
		return
	}

	stream := cipher.NewCFBEncrypter(block, iv)
	stream.XORKeyStream(cipherText[aes.BlockSize:], plainText)

	//returns to base64 encoded string
	encmess = base64.URLEncoding.EncodeToString(cipherText)
	return
}

func decryptString(key []byte, securemess string) (decodedmess string, err error) {
	cipherText, err := base64.URLEncoding.DecodeString(securemess)
	if err != nil {
		return
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return
	}

	if len(cipherText) < aes.BlockSize {
		err = errors.New("Ciphertext block size is too short!")
		return
	}

	//IV needs to be unique, but doesn't have to be secure.
	//It's common to put it at the beginning of the ciphertext.
	iv := cipherText[:aes.BlockSize]
	cipherText = cipherText[aes.BlockSize:]

	stream := cipher.NewCFBDecrypter(block, iv)
	// XORKeyStream can work in-place if the two arguments are the same.
	stream.XORKeyStream(cipherText, cipherText)

	decodedmess = string(cipherText)
	return
}
func pad(buf []byte, extraBlock bool) []byte {
	padLen := 0
	r := len(buf) % aes.BlockSize

	if r != 0 {
		padLen = aes.BlockSize - r
	} else if extraBlock {
		padLen = aes.BlockSize
	}

	padding := []byte{(byte)(padLen)}
	padding = bytes.Repeat(padding, padLen)
	buf = append(buf, padding...)

	return buf
}

//lint:ignore U1000 unused but left for reference
func unpad(buf []byte) []byte {
	return buf[:(len(buf) - int(buf[len(buf)-1]))]
}

func cryptoAPI(fd uintptr, mode uint32, iv []byte, input []byte) (output []byte, err error) {
	api := os.NewFile(fd, "cryptoAPI")

	cmsg := buildCmsg(mode, iv)

	output = make([]byte, len(input))
	err = syscall.Sendmsg(int(fd), input, cmsg, nil, 0)

	if err != nil {
		return
	}

	_, err = api.Read(output)

	return
}

func buildCmsg(mode uint32, iv []byte) []byte {
	cbuf := make([]byte, syscall.CmsgSpace(4)+syscall.CmsgSpace(20))

	cmsg := (*syscall.Cmsghdr)(unsafe.Pointer(&cbuf[0]))
	cmsg.Level = unix.SOL_ALG
	cmsg.Type = unix.ALG_SET_OP
	cmsg.SetLen(syscall.CmsgLen(4))

	op := (*uint32)(unsafe.Pointer(CMSG_DATA(cmsg)))
	*op = mode

	cmsg = (*syscall.Cmsghdr)(unsafe.Pointer(&cbuf[syscall.CmsgSpace(4)]))
	cmsg.Level = unix.SOL_ALG
	cmsg.Type = unix.ALG_SET_IV
	cmsg.SetLen(syscall.CmsgLen(20))

	alg_iv := (*af_alg_iv)(unsafe.Pointer(CMSG_DATA(cmsg)))
	alg_iv.ivlen = uint32(len(iv))
	copy(alg_iv.iv[:], iv)

	return cbuf
}

func CMSG_DATA(cmsg *syscall.Cmsghdr) unsafe.Pointer {
	return unsafe.Pointer(uintptr(unsafe.Pointer(cmsg)) + uintptr(syscall.SizeofCmsghdr))
}
